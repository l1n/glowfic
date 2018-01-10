require "spec_helper"

RSpec.feature "Renders the same:", :type => :feature, :js => true do
  let(:desired_time) { Time.zone.local(2018) }

  shared_examples_for "layout" do |layout|
    let(:icon) { create(:icon, url: "https://dummyimage.com/100x100/000/fff.png", keyword: "a") }
    let(:user) { create(:user, username: 'Jane Doe', email: 'fake303@faker.com', password: 'known', avatar: icon) }

    before(:each) do
      user.update_attributes(layout: layout)

      visit root_path
      fill_in "username", with: user.username
      fill_in "password", with: 'known'
      click_button "Log in"
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
        icon = create(:icon, url: "https://dummyimage.com/100x100/000/fff.png", galleries: [gallery])
        2.times { create(:icon, url: "https://dummyimage.com/100x100/000/fff.png", galleries: [gallery]) }
        character.galleries += [gallery]
        character.update_attributes(default_icon: icon)
        visit edit_character_path(character)
      end
      expect(page).to match_expectation
    end

    scenario "Gallery" do
      Timecop.freeze(desired_time) do
        4.times do |i|
          create(:gallery_group, user: user, name: "Tag#{i+1}")
        end
        gallery = create(:gallery, user: user, gallery_groups: GalleryGroup.all)
        gallery.icons = Array.new(10) do |i|
          create(:icon, url: "https://dummyimage.com/100x100/000/fff.png", keyword: i)
        end
        visit gallery_path(gallery)
      end
      expect(page).to match_expectation
    end

    context "with post" do
      let(:other_user) { create(:user, username: 'John Doe') }
      let(:character1) { create(:character, name: "Alice", user: user) }
      let(:post) do
        Timecop.freeze(desired_time) do
          warnings = Array.new(5) do |i|
            create(:content_warning, name: "warning #{i+1}", user: user)
          end
          settings = Array.new(2) do |i|
            create(:setting, name: "test setting #{i+1}", user: user)
          end
          labels = Array.new(3) do |i|
            create(:label, name: "test tag #{i+1}", user: user)
          end
          create(:post,
            user: user,
            character: character1,
            subject: 'Crypto Problems',
            description: "test subtitle",
            board: create(:board, name: 'Testing Area', id: 5),
            settings: settings,
            content_warnings: warnings,
            labels: labels
          )
        end
      end

      before(:each) do
        Timecop.freeze(desired_time) do
          character2 = create(:character, name: "Bob", user: other_user)
          30.times do |i|
            if i.even?
              create(:reply, post: post, user: other_user, character: character2)
            elsif i.odd?
              create(:reply, post: post, user: user, character: character1)
            end
          end
        end
      end

      scenario "Post" do
        Timecop.freeze(desired_time) do
          visit post_path(post, page: 2)
          sleep(0.5)
        end
        expect(page).to match_expectation
      end

      scenario "Post#Edit" do
        Timecop.freeze(desired_time) do
          visit edit_post_path(post)
          sleep(0.5)
        end
        expect(page).to match_expectation
      end

      scenario "Post#Metadata" do
        Timecop.freeze(desired_time) do
          character3 = create(:character, name: "Eve", user: user)
          create(:reply, post: post, user: user, character: character3)
          visit stats_post_path(post)
        end
        expect(page).to match_expectation
      end

      scenario "Icon Picker" do
        user.update_attributes(default_editor: 'html')
        Timecop.freeze(desired_time) do
          galleries = Array.new(3) do |i|
            gallery = create(:gallery, user: user)
            n = (i == 1) ? 9 : 3
            n.times do
              create(:icon, url: "https://dummyimage.com/100x100/000/fff.png", keyword: i, galleries: [gallery])
            end
            gallery
          end
          character1.update_attributes(galleries: galleries)
          visit post_path(post, page: 2)
        end
        page.find('#current-icon-holder img').click
        expect(page).to match_expectation
      end
    end
  end

  ['default', 'dark', 'starry', 'starrydark', 'starrylight', 'monochrome', 'river', 'iconless'].each do |type|
    context type do
      it_behaves_like('layout', (type == 'default') ? nil : type)
    end
  end
end
