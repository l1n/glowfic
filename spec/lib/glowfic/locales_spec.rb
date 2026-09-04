RSpec.describe Glowfic::Locales do
  describe ".valid_tag?" do
    it "accepts a bare language" do
      expect(Glowfic::Locales.valid_tag?('es')).to be(true)
    end

    it "accepts a language with a region" do
      expect(Glowfic::Locales.valid_tag?('pt-BR')).to be(true)
    end

    it "accepts a language with a script" do
      expect(Glowfic::Locales.valid_tag?('zh-Hant')).to be(true)
    end

    it "accepts a language with a script and a region" do
      expect(Glowfic::Locales.valid_tag?('zh-Hant-HK')).to be(true)
    end

    it "rejects free text" do
      expect(Glowfic::Locales.valid_tag?('not a language')).to be(false)
    end

    it "rejects markup smuggled into the value" do
      expect(Glowfic::Locales.valid_tag?('es" onload="alert(1)')).to be(false)
    end

    it "rejects a mis-cased region" do
      expect(Glowfic::Locales.valid_tag?('pt-br')).to be(false)
    end

    it "rejects a non-string" do
      expect(Glowfic::Locales.valid_tag?(nil)).to be(false)
    end
  end

  describe ".base_code" do
    it "drops the region" do
      expect(Glowfic::Locales.base_code('pt-BR')).to eq('pt')
    end

    it "is nil for a blank value" do
      expect(Glowfic::Locales.base_code(nil)).to be_nil
    end
  end

  describe ".rtl?" do
    it "is true for Hebrew" do
      expect(Glowfic::Locales.rtl?('he')).to be(true)
    end

    it "is true for a region of a right-to-left language" do
      expect(Glowfic::Locales.rtl?('ar-EG')).to be(true)
    end

    it "is false for Spanish" do
      expect(Glowfic::Locales.rtl?('es')).to be(false)
    end
  end

  describe ".ui_codes" do
    it "includes English even though it has no po file" do
      expect(Glowfic::Locales.ui_codes).to include('en')
    end

    it "includes languages that have a po file" do
      expect(Glowfic::Locales.ui_codes).to include('es')
    end
  end
end
