class DumpCoordinate
  include ActiveModel::Model
  require 'csv'

  class << self
    # 都道府県別1kmメッシュ https://www.geospatial.jp/ckan/dataset/npli-pref-1km
    def remove_duplication_output
      CSV.open('愛知県1km毎_重複削除.csv', 'w') do |csv|
        CSV.read('愛知県1km毎.csv').uniq.each { |r| csv << r }
      end
    end
  end
end