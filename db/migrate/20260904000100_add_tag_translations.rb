class AddTagTranslations < ActiveRecord::Migration[8.0]
  def change
    # A tag's name/description in one language. The row on `tags` stays the
    # canonical (source-language) copy, so nothing existing has to be backfilled
    # and a tag with no translations behaves exactly as it does today.
    create_table :tag_translations do |t|
      t.integer :tag_id, null: false
      t.string :locale, null: false
      t.citext :name, null: false
      t.text :description
      t.timestamps null: true
    end
    add_index :tag_translations, :tag_id
    add_index :tag_translations, [:tag_id, :locale], unique: true
    add_index :tag_translations, :name

    # The language the canonical name/description on `tags` itself is written in.
    # NULL means "the site default", which is what every existing tag is.
    add_column :tags, :locale, :string
  end
end
