desc "UberEATS全店舗マップの情報取得と更新開始"
task update_ubereats_mymap: :environment do
  Store.edit_tokyo_mymaps
  Store.edit_osaka_mymaps
  Store.edit_yokohama_mymaps
  Store.edit_kyoto_mymaps
  Store.edit_kobe_mymaps
  Store.edit_saitama_mymaps
  Store.edit_nagoya_mymaps
  Store.edit_fukuoka_mymaps
end
