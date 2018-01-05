require "spec_helper"

RSpec.feature "Renders the same:", :type => :feature, :js => true do
  let(:desired_time) { Time.zone.local(2018) }

  shared_examples_for "layout" do |layout|
    let(:user) {
       user = create(:user, username: 'Jane Doe', email: 'fake303@faker.com', password: 'known')
       visit root_path
       fill_in "username", with: user.username
       fill_in "password", with: 'known'
       click_button "Log in"
       user }
    before(:each) do
      user.update_attributes(layout: layout)
    end

    scenario "Recently Updated" do
      Timecop.freeze(desired_time) do
        board = create(:board, name: 'Testing Area', creator: user)
        26.times do |i|
          create(:post, user: user, board: board, subject: "test subject #{i+1}")
        end
        visit posts_path
      end
      expect(page).to match_expectation
    end

    scenario "User#Edit" do
      Timecop.freeze(desired_time) do
        visit edit_user_path(user)
      end
      expect(page).to match_expectation
    end

    scenario "Board" do
      Timecop.freeze(desired_time) do
        other_user = create(:user, username: 'John Doe')
        board = create(:board, name: 'Testing Area', id: 3)
        3.times do |i|
          create(:board_section, board: board, name: "Test Section #{i+1}")
        end
        2.times { create(:post, board: board, user: user, subject: 'test subject') }
        create(:post, board: board, user: other_user, subject: 'test subject')
        board.board_sections.order(:section_order).each do |section|
          create(:post, board: board, section: section, user: user, subject: 'test subject')
          create(:post, board: board, section: section, user: other_user, subject: 'test subject')
        end
        visit board_path(board)
      end
      expect(page).to match_expectation
    end

    scenario "Character#Edit" do
      Timecop.freeze(desired_time) do
        character = create(:character, user: user, name: 'test character 1')
        gallery = create(:gallery, user: user)
        icon = create(:icon, user: user, galleries: [gallery])
        2.times { create(:icon, user: user, galleries: [gallery]) }
        character.galleries += [gallery]
        character.update_attributes(default_icon: icon)
        visit edit_character_path(character)
      end
      expect(page).to match_expectation
    end

    scenario "Post" do
      Timecop.freeze(desired_time) do
        other_user = create(:user, username: 'John Doe')
        post = create(:post, user: other_user, subject: 'test subject', board: create(:board, name: 'test board', id: 5))
        create(:reply, post: post, user: user)
        30.times do |i|
          if i.even? then
            create(:reply, post: post, user: user)
          else
            create(:reply, post: post, user: other_user)
          end
        end
        visit post_path(post, page: 2)
        sleep(0.5)
      end
      expect(page).to match_expectation
    end

    scenario "Post#Edit" do
      Timecop.freeze(desired_time) do
        post = create(:post, user: user, subject: 'test subject', board: create(:board, name: 'test board', id: 5))
        visit edit_post_path(post)
        sleep(0.5)
      end
      expect(page).to match_expectation
    end

    scenario "Gallery" do
      Timecop.freeze(desired_time) do
        4.times do |i|
          create(:gallery_group, user: user, name: "Tag#{i+1}")
        end
        gallery = create(:gallery, user: user, gallery_groups: GalleryGroup.all)
        10.times do |i|
          gallery.icons += [create(:icon, url: "https://dummyimage.com/100x100/000/fff.png", keyword: i)]
        end
        visit gallery_path(gallery)
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
