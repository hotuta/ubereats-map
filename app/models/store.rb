class Store < ApplicationRecord
  @session = Capybara::Session.new(:chrome)

  class << self
    def edit_tokyo_mymaps
      # https://www.google.com/maps/d/u/0/viewer?mid=1Xuly26goLsPFmF_ehhmefrWdyV8
      get_maps 'https://www.google.com/maps/d/u/0/kml?mid=1Xuly26goLsPFmF_ehhmefrWdyV8&forcekml=1'
      get_stores("Tokyo")
      parse_and_edit_kml("Tokyo")
      upload_kmz('https://www.google.com/maps/d/u/0/edit?mid=1koUCzDuaDiufkHOmH9bmB5lEXOs')
    end

    def edit_yokohama_mymaps
      get_maps 'https://www.google.com/maps/d/u/0/kml?mid=1BAoMqt-4b8iEEbAIgP_MlqBskEs&forcekml=1'
      get_stores("Yokohama")
      parse_and_edit_kml("Yokohama")
      upload_kmz('https://www.google.com/maps/d/u/0/edit?mid=1C8dBMymzR89lByKZFHw4GNEv_4les6-z')
    end

    def edit_osaka_mymaps
      # FIXME: エリアマップが公開されたら修正する
      @latitude_max = "34.757389".to_f
      @latitude_min = "34.657389".to_f

      @longitude_max = "135.588139".to_f
      @longitude_min = "135.448139".to_f

      get_stores("Osaka")
      parse_and_edit_kml("Osaka")
      upload_kmz('https://www.google.com/maps/d/u/0/edit?mid=1h4ymDuwne5AULxnhEe9I4UlgZPf-NGbO')
    end

    def edit_kawasaki_mymaps
      @coordinates = JSON.load(File.read ("kawasaki_coordinates.json"))
      # TODO: DBを分ける
      get_stores("Tokyo")
      parse_and_edit_kml("Tokyo")
      upload_kmz('https://www.google.com/maps/d/u/0/edit?mid=1f3HXzjohfLSD5VZC4YoVUMOqGFO0CGR8')
      @coordinates = ""
    end

    def dump_kawasaki_coodinates
      @prefecture = "神奈川県"
      @target = "川崎"
      get_coordinate
      File.open("kawasaki_coordinates.json", 'w') do |f|
        JSON.dump(@coordinates, f)
      end
    end

    def get_res_to_obj(url, headers)
      res = RestClient.get(url, headers)
      json = res.body
      JSON.parse(json, object_class: OpenStruct).response
    end

    def get_extract_cities
      cities = get_res_to_obj("http://geoapi.heartrails.com/api/json", {params: {method: 'getCities', prefecture: @prefecture}}).location
      cities.map do |city_struct|
        city_struct.city if city_struct.city.start_with?(@target)
      end.compact!
    end

    def get_coordinate
      @coordinates = []
      get_extract_cities.each do |extract_city|
        towns = get_res_to_obj("http://geoapi.heartrails.com/api/json", {params: {method: 'getTowns', prefecture: @prefecture, city: extract_city}}).location
        if towns.count == 400
          hoge = 1
          break
        end
        towns.each do |town|
          @coordinates << [town.x, town.y]
        end
      end
    end

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

      if @coordinates.present?
        puts "coordinates"
        @coordinates.each do |longitude, latitude|
          longitude_array << longitude.to_f
          latitude_array << latitude.to_f
        end
      else
        puts "latitude"
        @latitude_min.step(@latitude_max, 0.008) do |latitude|
          latitude_array << latitude
        end
        @longitude_min.step(@longitude_max, 0.008) do |longitude|
          longitude_array << longitude
        end
      end

      time = Time.now

      bodies = []
      latitude_array.zip(longitude_array).each do |latitude, longitude|
        bodies << {targetLocation: {latitude: latitude, longitude: longitude}, feedTypes: ["STORE", "SEE_ALL_STORES"]}
      end

      ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
        Parallel.each(bodies, in_processes: 3) do |body|
          sleep 2

          predictions_res = RestClient.get('https://www.ubereats.com/rtapi/locations/v2/predictions') {|predictions_response| predictions_response}
          header = {x_csrf_token: predictions_res.headers[:x_csrf_token], content_type: 'application/json', Connection: 'keep-alive', cookies: predictions_res.cookies}
          res = RestClient.post('https://www.ubereats.com/rtapi/eats/v1/bootstrap-eater', body.to_json, header) {|response| response}

          json = res.body
          hash = JSON.parse(json) rescue next
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

          columns = Store.column_names - ["id", "url", "created_at", "updated_at"]
          Concurrent::Future.execute do
            ActiveRecord::Base.connection_pool.with_connection do
              Rails.application.executor.wrap do
                Store.import stores, recursive: true, on_duplicate_key_update: {conflict_target: [:url], columns: columns}
              end
            end
          end
        end
      end
    end

    def parse_and_edit_kml(area)
      Store.where(area: area).find_in_batches(batch_size: 2000).with_index(1) do |group, i|
        kml_file = "map/doc.kml"
        file = File.read(kml_file)
        @doc = Nokogiri::XML(file) do |config|
          config.strict.noblanks
        end
        @doc.remove_namespaces!

        @doc.xpath('//Folder/Placemark').remove

        layer_name = @doc.xpath('//Folder/name').first
        layer_name.content = "#{DateTime.now.strftime('%-m月%d日%H時%M分')}現在_全#{Store.where(area: area).count}店舗_Part#{i}"

        group.each do |store|
          # TODO: 店舗URLもマップに追加したい
          @doc.at('Folder').add_child("<Placemark><styleUrl>#icon-1739-0288D1</styleUrl><name>#{store.name}</name><Point><coordinates>#{store.longitude}, #{store.latitude}</coordinates></Point></Placemark>")
        end

        f = File.new(kml_file, "w")
        f << @doc.to_xml
        f.close

        Archive::Zip.archive("kmz_map/part#{i}_edit_map.kmz", 'map/.')
      end
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

      kmz_files = Dir.glob('kmz_map/*.kmz')
      kmz_files_count = kmz_files.count

      puts "KMZファイル#{kmz_files_count}個"

      # 既に空のレイヤーが追加されている場合は削除する
      @delete_layer_xpath = "//div[@id='ly#{kmz_files_count}-layer-header']/div[3]"
      @delete_has_xpath = @delete_layer_xpath
      delete_layer_has_xpath if kmz_files_count.present?

      kmz_files.each do |filename|
        @session.find(:id, "map-action-add-layer").click
        sleep 15
        @session.refresh
        sleep 15
        layer_count = @session.all(:xpath, "//div[contains(@id, 'layer-header')]").count
        @session.find(:id, "ly#{layer_count - 1}-layerview-import-link").hover.click
        sleep 15

        html = @session.driver.browser.page_source
        doc = Nokogiri::HTML(html)

        frame_text = doc.xpath("/html/body/div/div[2]/iframe").attribute("id").text
        frame = @session.find(:frame, frame_text)
        @session.switch_to_frame(frame)

        file = File.join(Dir.pwd, filename)
        @session.find(:xpath, "//*[@id='doclist']/div/div[4]/div[2]/div/div[2]/div/div/div[1]/div/div[2]/input[@type='file']", visible: false).send_keys file

        sleep 15
        puts "switch前"
        @session.switch_to_frame(:top)
        puts "switch後"

        # レイヤーを消す
        @delete_layer_xpath = "//div[@id='ly0-layer-header']/div[3]"
        delete_layer_has_xpath
        File.delete file
      end

      @session.driver.quit
    end

    def delete_layer_has_xpath
      loop do
        @session.refresh
        sleep 15
        if @session.has_xpath?(@delete_has_xpath)
          puts @delete_layer_xpath
          @session.find(:xpath, @delete_layer_xpath, visible: false).hover.click
          sleep 5
          puts "hoge"
          @session.all(:xpath, "//*[@id='layerview-menu']/div[2]/div", visible: false).first.hover.click
          sleep 10
          puts "hoge2"
          @session.find(:xpath, "//*[@id='cannot-undo-dialog']/div[3]/button[1]", visible: false).hover.click
          puts "hoge3"
          sleep 15
        else
          break
        end
      end
    end
  end
end
