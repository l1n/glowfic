# frozen_string_literal: true
class AddPreferredLanguagesToUsers < ActiveRecord::Migration[8.0]
  def change
    # The languages a user reads, best first. Tag names are shown in the first of these
    # that has a translation, and "Automatic" interface language means the first of these
    # the interface has been translated into. Empty means "just the interface language".
    add_column :users, :preferred_languages, :string, array: true, null: false, default: []
  end
end
