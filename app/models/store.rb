class Store < ApplicationRecord
  @session = Capybara::Session.new(:chrome)

  def self.edit_tokyo_mymaps
    get_maps 'https://www.google.com/maps/d/u/0/kml?mid=1Xuly26goLsPFmF_ehhmefrWdyV8&forcekml=1'
    get_stores("Tokyo")
    parse_and_edit_kml("Tokyo")
    upload_kmz('https://www.google.com/maps/d/u/0/edit?mid=1koUCzDuaDiufkHOmH9bmB5lEXOs')
  end

  def self.edit_yokohama_mymaps
    get_maps 'https://www.google.com/maps/d/u/0/kml?mid=1BAoMqt-4b8iEEbAIgP_MlqBskEs&forcekml=1'
    get_stores("Yokohama")
    parse_and_edit_kml("Yokohama")
    upload_kmz('https://www.google.com/maps/d/u/0/edit?mid=1C8dBMymzR89lByKZFHw4GNEv_4les6-z')
  end

  def self.edit_osaka_mymaps
    # FIXME: エリアマップが公開されたら修正する
    @latitude_max = "34.757389".to_f
    @latitude_min = "34.657389".to_f

    @longitude_max = "135.588139".to_f
    @longitude_min = "135.448139".to_f

    get_stores("Osaka")
    parse_and_edit_kml("Osaka")
    upload_kmz('https://www.google.com/maps/d/u/0/edit?mid=1h4ymDuwne5AULxnhEe9I4UlgZPf-NGbO')
  end

  class << self
    private

    def get_maps(map_url)
      map = RestClient.get map_url
      File.open('map.kml', 'w') do |f|
        f.print map
      end

      File.open('map.kml', 'r') do |f|
        file = f.read
        latitudes = file.scan(/,(\d{2}.[0-9]*)/)
        longitudes = file.scan(/(\d{3}.\d{6}),/)

        @latitude_max = latitudes.max.first.to_f
        @latitude_min = latitudes.min.first.to_f

        @longitude_max = longitudes.max.first.to_f
        @longitude_min = longitudes.min.first.to_f
      end
    end

    def get_stores(area)
      latitude_array = []
      longitude_array = []

      @latitude_min.step(@latitude_max, 0.008) do |latitude|
        latitude_array << latitude
      end
      @longitude_min.step(@longitude_max, 0.008) do |longitude|
        longitude_array << longitude
      end

      time = Time.now

      ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
        Parallel.each(latitude_array, in_processes: 2) do |latitude|
          Parallel.each(longitude_array, in_processes: 2) do |longitude|
            Rails.application.executor.wrap do
              sleep 2

              predictions_res = RestClient.get('https://www.ubereats.com/rtapi/locations/v2/predictions') {|predictions_response| predictions_response}
              body = {targetLocation: {latitude: latitude, longitude: longitude}, feedTypes: ["STORE", "SEE_ALL_STORES"]}
              header = {x_csrf_token: predictions_res.headers[:x_csrf_token], content_type: 'application/json', Connection: 'keep-alive', cookies: predictions_res.cookies}
              res = RestClient.post('https://www.ubereats.com/rtapi/eats/v1/bootstrap-eater', body.to_json, header) {|response| response}

              json = res.body
              hash = JSON.parse(json)
              next if hash["marketplace"]["feed"].empty? rescue nil
              parsed = hash["marketplace"]["feed"]["storesMap"] rescue nil
              next if parsed.empty? rescue nil
              next if parsed.nil?

              stores = []
              parsed.each.with_index(1) do |store|
                stores_hash = store[1]
                store = Store.new
                store.area = area
                store.url = "https://www.ubereats.com/stores/#{stores_hash["uuid"]}"
                store.name = stores_hash["title"].gsub(/'/, "''")
                store.coordinates = "#{stores_hash["location"]["latitude"]},#{stores_hash["location"]["longitude"]}"
                store.latitude = stores_hash["location"]["latitude"]
                store.longitude = stores_hash["location"]["longitude"]
                store.registered_at = time
                stores << store
              end
              Store.import stores, recursive: true, on_duplicate_key_update: {conflict_target: [:url], columns: [:name, :coordinates, :latitude, :longitude, :registered_at]}
            end
          end
        end
      end
    end

    def parse_and_edit_kml(area)
      file = File.read("map/doc.kml")
      @doc = Nokogiri::XML(file) do |config|
        config.strict.noblanks
      end
      @doc.remove_namespaces!

      @doc.xpath('//Folder/Placemark').remove

      layer_name = @doc.xpath('//Folder/name').first
      layer_name.content = "#{DateTime.now.strftime('%-m月%d日%H時%M分')}現在_全#{Store.where(area: area).count}店舗"

      Store.where(area: area).find_each do |store|
        # TODO: 店舗URLもマップに追加したい
        @doc.at('Folder').add_child("<Placemark><styleUrl>#icon-1739-0288D1</styleUrl><name>#{store.name}</name><Point><coordinates>#{store.longitude}, #{store.latitude}</coordinates></Point></Placemark>")
      end

      f = File.new("map/doc.kml", "w")
      f << @doc.to_xml
      f.close

      Archive::Zip.archive('edit_map.kmz', 'map/.')
    end

    def upload_kmz(map_url)
      @session.visit map_url
      # YAMLファイルにCookie情報をエクスポート
      # File.open('./yaml.dump', 'w') {|f| f.write(YAML.dump(@session.driver.browser.manage.all_cookies))}
      YAML.load(Base64.strict_decode64(ENV['YAML_DUMP'])).each do |d|
        @session.driver.browser.manage.add_cookie d
      end
      @session.visit map_url

      # FIXME: sleepは暫定措置
      sleep 15

      # 既に空のレイヤーが追加されている場合は削除する
      if @session.has_xpath?("//div[@id='ly1-layer-header']/div[3]")
        delete_layer("//div[@id='ly1-layer-header']/div[3]")
        sleep 10
        @session.visit map_url
      end

      sleep 15
      @session.find(:id, "map-action-add-layer").click
      sleep 15
      @session.find(:id, "ly1-layerview-import-link").click
      sleep 15

      html = @session.driver.browser.page_source
      doc = Nokogiri::HTML(html)

      frame = doc.xpath("/html/body/div/div[2]/iframe").attribute("id").text
      @session.driver.browser.switch_to.frame frame

      filename = 'edit_map.kmz'
      file = File.join(Dir.pwd, filename)
      @session.find(:xpath, "//*[@id='doclist']/div/div[4]/div[2]/div/div[2]/div/div/div[1]/div/div[2]/input[@type='file']", visible: false).send_keys file

      @session.driver.browser.switch_to.window @session.driver.browser.window_handle

      # レイヤーを消す
      sleep 15
      delete_layer("//div[@id='ly0-layer-header']/div[3]")
      sleep 15
      @session.driver.quit
      File.delete 'edit_map.kmz'
    end

    def delete_layer(layer_xpath)
      @session.find(:xpath, layer_xpath, visible: false).click
      sleep 10
      @session.find(:xpath, "//*[@id='layerview-menu']/div[2]/div", visible: false).click
      sleep 10
      @session.find(:xpath, "//*[@id='cannot-undo-dialog']/div[3]/button[1]", visible: false).click
    end
  end
end
