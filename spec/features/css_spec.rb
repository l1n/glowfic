require "spec_helper"

RSpec.feature "Renders the same:", :type => :feature, :js => true do
  before(:each) do
    4.times { create(:board).destroy }
    desired_time = Time.zone.local(2018)
    Timecop.freeze(desired_time) do
      26.times { create(:post) }
    end
  end

  shared_examples_for "layout" do |layout|
    before(:each) do
      user = login
      user.update_attributes(layout: layout)
    end

    scenario "Recently Updated" do
      Timecop.freeze(Time.zone.local(2018)) do
        visit posts_path
      end
      expect(page).to match_expectation
    end
  end

  ['default', 'dark', 'starry', 'starrydark', 'starrylight', 'monochrome', 'river', 'iconless'].each do |type|
    context type do
      it_behaves_like('layout', (type == 'default') ? nil : type)
    end
  end
end
