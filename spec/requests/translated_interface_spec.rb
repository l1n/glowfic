RSpec.describe "Translated interface" do
  it "renders the navigation in the language the browser asks for" do
    get root_path, headers: { 'HTTP_ACCEPT_LANGUAGE' => 'es' }

    expect(response.body).to include('Continuidades')
    expect(response.body).to include('Etiquetas')
    expect(response.body).to include('Iniciar sesión')
  end

  it "announces the page's language on the html element" do
    get root_path, headers: { 'HTTP_ACCEPT_LANGUAGE' => 'es' }
    expect(response.body).to include('lang="es"')
  end

  it "stays in English when nothing asks for anything else" do
    get root_path
    expect(response.body).to include('Continuities')
  end

  it "keeps the Setting tag type apart from the account settings page" do
    I18n.with_locale(:es) do
      expect(tag_helper.tag_type_plural('Setting')).to eq('Ambientaciones')
      expect(_("Settings")).to eq('Configuración')
    end
  end

  it "shows a tag's translated name, and its type, to a reader of that language" do
    tag = create(:setting, name: 'Amber', locale: 'en')
    create(:tag_translation, tag: tag, locale: 'es', name: 'Ámbar')

    get tag_path(tag), headers: { 'HTTP_ACCEPT_LANGUAGE' => 'es' }

    expect(response.body).to include('Ámbar')
    expect(response.body).to include('Ambientación')
  end

  it "follows the reader's preferences for both the interface and the tag names" do
    tag = create(:setting, name: 'Amber', locale: 'en')
    create(:tag_translation, tag: tag, locale: 'pt', name: 'Âmbar')
    create(:tag_translation, tag: tag, locale: 'es', name: 'Ámbar')
    reader = create(:user, preferred_languages: ['pt', 'es'])

    login(reader)
    get tag_path(tag)

    # the interface has no Portuguese, so it falls through to the reader's second choice…
    expect(response.body).to include('<html lang="es">')
    expect(response.body).to include('Ambientación')
    # …while the tag name, which does exist in Portuguese, follows their first, and says so
    expect(response.body).to include('<span lang="pt">Âmbar</span>')
  end

  it "marks a tag name that isn't in the reader's language with the language it is in" do
    tag = create(:setting, name: 'こはく', locale: 'ja')

    get tag_path(tag)

    expect(response.body).to include('<span lang="ja">こはく</span>')
  end

  def tag_helper
    @tag_helper ||= Class.new { include TagHelper }.new
  end
end
