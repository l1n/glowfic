RSpec.describe TagHelper do
  describe "#localized_tag_name" do
    let(:tag) { create(:setting, name: 'Amber', locale: 'en') }

    it "returns the canonical name unwrapped when it's in the page's language" do
      expect(helper.localized_tag_name(tag)).to eq('Amber')
    end

    it "wraps a translation in a span carrying its language" do
      create(:tag_translation, tag: tag, locale: 'es', name: 'Ámbar')
      I18n.with_locale(:es) do
        expect(helper.localized_tag_name(tag.reload)).to eq('Ámbar')
      end
    end

    it "marks up a name that isn't in the page's language" do
      japanese = create(:setting, name: 'こはく', locale: 'ja')
      expect(helper.localized_tag_name(japanese)).to eq('<span lang="ja">こはく</span>')
    end

    it "adds a direction for right-to-left languages" do
      hebrew = create(:setting, name: 'ענבר', locale: 'he')
      expect(helper.localized_tag_name(hebrew)).to eq('<span lang="he" dir="rtl">ענבר</span>')
    end

    it "resolves the name against the reader's preferred languages" do
      create(:tag_translation, tag: tag, locale: 'es', name: 'Ámbar')
      create(:tag_translation, tag: tag, locale: 'pt', name: 'Âmbar')
      reader = build(:user, preferred_languages: ['pt', 'es'])
      without_partial_double_verification do
        allow(helper).to receive(:current_user).and_return(reader)
      end
      expect(helper.localized_tag_name(tag.reload)).to eq('<span lang="pt">Âmbar</span>')
    end

    it "escapes the name it wraps" do
      sneaky = create(:setting, name: '<script>', locale: 'ja')
      expect(helper.localized_tag_name(sneaky)).to eq('<span lang="ja">&lt;script&gt;</span>')
    end
  end

  describe "#localized_attrs" do
    it "is empty when the text is in the page's language" do
      expect(helper.localized_attrs(Tag::Localized.new('Amber', 'en'))).to eq({})
    end

    it "carries lang for another language" do
      expect(helper.localized_attrs(Tag::Localized.new('Ámbar', 'es'))).to eq({ lang: 'es' })
    end
  end

  describe "#delete_path" do
    let(:tag) { create(:setting) }

    it "returns the right url with no params" do
      expect(helper.delete_path(tag)).to eq(tag_path(tag))
    end

    it "returns the right url with a page" do
      without_partial_double_verification do
        allow(helper).to receive_messages(params: { page: 2 }, page: 2)
      end
      expect(helper.delete_path(tag)).to eq(tag_path(tag, { page: 2 }))
    end

    it "returns the right url with a view" do
      assign(:view, 'Setting')
      expect(helper.delete_path(tag)).to eq(tag_path(tag, { view: 'Setting' }))
    end
  end
end
