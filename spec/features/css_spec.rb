require "spec_helper"

RSpec.feature "Recently updated renders the same", :type => :feature, :js => true do
  before(:each) do
    puts 'test'
    26.times { create(:post) }
    puts Post.count
  end
  scenario "in default" do
    user = login
    user.update_attributes(layout: 'default')
    visit posts_path
    puts page.text
    expect(page).to match_expectation
  end
end
