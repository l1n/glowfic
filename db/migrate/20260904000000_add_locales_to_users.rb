# frozen_string_literal: true
class AddLocalesToUsers < ActiveRecord::Migration[8.0]
  def change
    change_table :users, bulk: true do |t|
      # Which language to show the interface in. NULL means "work it out from the
      # browser's Accept-Language", so existing users aren't pinned to English.
      t.string :locale

      # The language this user writes in, used to seed the editor's language buttons
      # and the tag translation editor. NULL means the site default.
      t.string :content_language
    end
  end
end
