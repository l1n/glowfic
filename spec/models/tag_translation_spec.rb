RSpec.describe TagTranslation do
  describe "validations" do
    it "requires a known language" do
      translation = build(:tag_translation, locale: 'klingon')
      expect(translation).not_to be_valid
      expect(translation.errors[:locale]).to be_present
    end

    it "requires a name" do
      expect(build(:tag_translation, name: nil)).not_to be_valid
    end

    it "allows one translation per language per tag" do
      translation = create(:tag_translation, locale: 'es')
      duplicate = build(:tag_translation, tag: translation.tag, locale: 'es')
      expect(duplicate).not_to be_valid
    end

    it "allows the same language on different tags" do
      create(:tag_translation, locale: 'es')
      expect(build(:tag_translation, locale: 'es')).to be_valid
    end
  end

  describe "#language_name" do
    it "gives the language's own name for it" do
      expect(build(:tag_translation, locale: 'es').language_name).to eq('Español')
    end
  end

  describe "#rtl?" do
    it "is true for right-to-left languages" do
      expect(build(:tag_translation, locale: 'he')).to be_rtl
    end

    it "is false for left-to-right languages" do
      expect(build(:tag_translation, locale: 'es')).not_to be_rtl
    end
  end
end
