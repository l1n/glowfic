require "spec_helper"

RSpec.feature "Renders the same:", :type => :feature, :js => true do
  before(:each) do
    4.times { create(:board).destroy }
    desired_time = Time.zone.local(2018)
    Timecop.freeze(desired_time) do
      26.times { create(:post) }
    end
  end

  scenario "default"
    before(:each) do
      user = login
      user.update_attributes(layout: nil)
    end

    scenario "Recently Updated" do
      Timecop.freeze(Time.zone.local(2018)) do
        visit posts_path
      end
      expect(page).to match_expectation
    end

    scenario "User#Edit" do
      Timecop.freeze(Time.zone.local(2018)) do
        visit edit_user_path(user.id)
      end
      expect(page).to match_expectation
    end
  end

  scenario "dark"
    before(:each) do
      user = login
      user.update_attributes(layout: 'dark')
    end

    scenario "Recently Updated" do
      Timecop.freeze(Time.zone.local(2018)) do
        visit posts_path
      end
      expect(page).to match_expectation
    end
  end

  scenario "starry" do
    before(:each) do
      user = login
      user.update_attributes(layout: 'starry')
    end

    scenario "Recently Updated" do
      Timecop.freeze(Time.zone.local(2018)) do
        visit posts_path
      end
      expect(page).to match_expectation
    end
  end

  scenario "starrydark" do
    before(:each) do
      user = login
      user.update_attributes(layout: 'starrydark')
    end

    scenario "Recently Updated" do
      Timecop.freeze(Time.zone.local(2018)) do
        visit posts_path
      end
      expect(page).to match_expectation
    end

  scenario "starrylight" do
    before(:each) do
      user = login
      user.update_attributes(layout: 'starrylight')
    end

    scenario "Recently Updated" do
      Timecop.freeze(Time.zone.local(2018)) do
        visit posts_path
      end
      expect(page).to match_expectation
    end
  end

  scenario "monochrome" do
    before(:each) do
      user = login
      user.update_attributes(layout: 'monochrome')
    end

    scenario "Recently Updated" do
      Timecop.freeze(Time.zone.local(2018)) do
        visit posts_path
      end
      expect(page).to match_expectation
    end
  end

  scenario "river" do
    before(:each) do
      user = login
      user.update_attributes(layout: 'river')
    end

    scenario "Recently Updated" do
      Timecop.freeze(Time.zone.local(2018)) do
        visit posts_path
      end
      expect(page).to match_expectation
    end
  end

  scenario "iconless" do
    before(:each) do
      user = login
      user.update_attributes(layout: 'iconless')
    end

    scenario "Recently Updated" do
      Timecop.freeze(Time.zone.local(2018)) do
        visit posts_path
      end
      expect(page).to match_expectation
    end
  end
