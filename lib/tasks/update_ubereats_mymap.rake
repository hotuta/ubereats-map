desc "UberEATS全店舗マップの更新開始"

desc "東京エリアUberEATS全店舗マップの情報取得と更新開始"
task edit_tokyo_mymaps: :environment do
  Store.edit_tokyo_mymaps
end

desc "大阪エリアUberEATS全店舗マップの情報取得と更新開始"
task edit_osaka_mymaps: :environment do
  Store.edit_osaka_mymaps
end

desc "横浜エリアUberEATS全店舗マップの情報取得と更新開始"
task edit_yokohama_mymaps: :environment do
  Store.edit_yokohama_mymaps
end

desc "京都エリアUberEATS全店舗マップの情報取得と更新開始"
task edit_kyoto_mymaps: :environment do
  Store.edit_kyoto_mymaps
end

desc "神戸エリアUberEATS全店舗マップの情報取得と更新開始"
task edit_kobe_mymaps: :environment do
  Store.edit_kobe_mymaps
end

desc "埼玉エリアUberEATS全店舗マップの情報取得と更新開始"
task edit_saitama_mymaps: :environment do
  Store.edit_saitama_mymaps
end

desc "名古屋エリアUberEATS全店舗マップの情報取得と更新開始"
task edit_nagoya_mymaps: :environment do
  Store.edit_nagoya_mymaps
end

desc "福岡エリアUberEATS全店舗マップの情報取得と更新開始"
task edit_fukuoka_mymaps: :environment do
  Store.edit_fukuoka_mymaps
end
