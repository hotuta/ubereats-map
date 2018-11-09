require 'clockwork'
require './config/boot'
require './config/environment'

module Clockwork
  handler do |job|
    puts "Running #{job}"
  end

  every(1.hours, 'Store') do
    Store.edit_kawasaki_mymaps
    Store.edit_tokyo_mymaps
    Store.edit_osaka_mymaps
    Store.edit_yokohama_mymaps
    Store.edit_kyoto_mymaps
    Store.edit_kobe_mymaps
    Store.edit_saitama_mymaps
    Store.edit_nagoya_mymaps
  end
end
