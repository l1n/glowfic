RSpec.describe Glowfic::Sanitizers do
  describe ".written" do
    it "keeps a span marking a passage's language" do
      html = Glowfic::Sanitizers.written('<p>She said <span lang="es">buenos días</span>.</p>')
      expect(html).to eq('<p>She said <span lang="es">buenos días</span>.</p>')
    end

    it "keeps a language with a region" do
      expect(Glowfic::Sanitizers.written('<span lang="pt-BR">oi</span>')).to eq('<span lang="pt-BR">oi</span>')
    end

    it "keeps xml:lang alongside lang" do
      html = Glowfic::Sanitizers.written('<span lang="es" xml:lang="es">hola</span>')
      expect(html).to include('xml:lang="es"')
    end

    it "keeps a direction on right-to-left text" do
      expect(Glowfic::Sanitizers.written('<span lang="he" dir="rtl">שלום</span>')).to eq('<span lang="he" dir="rtl">שלום</span>')
    end

    it "drops a language that isn't a language tag" do
      expect(Glowfic::Sanitizers.written('<span lang="haha not a language">hi</span>')).to eq('<span>hi</span>')
    end

    it "drops a direction that isn't a direction" do
      expect(Glowfic::Sanitizers.written('<span dir="sideways">hi</span>')).to eq('<span>hi</span>')
    end

    it "leaves the text alone when it drops a bad language" do
      expect(Glowfic::Sanitizers.written('<span lang="../../etc">text</span>')).to eq('<span>text</span>')
    end
  end
end
