require "spec_helper"

RSpec.feature "Recently updated renders the same", :type => :feature, :js => true do
  before(:each) do
    4.times { create(:board).destroy }
    desired_time = Time.new(2018)
    Timecop.freeze(desired_time) do
      26.times { create(:post) }
    end
  end

  scenario "in default" do
    user = login
    user.update_attributes(layout: 'default')
    visit posts_path
    puts page.text
    expect(page).to match_expectation
  end
end
