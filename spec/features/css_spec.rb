require "spec_helper"

RSpec.feature "Renders the same:", :type => :feature, :js => true do
  let(:desired_time) { Time.zone.local(2018) }

  shared_examples_for "layout" do |layout|
    let(:user) { create(:user, username: 'Jane Doe', email: 'fake303@faker.com', password: 'known') }
    let(:other_user) { create(:user, username: 'John Doe') }

    before(:each) do
      user.update!(layout: layout)
      user.update!(avatar: create(:icon, user: user, url: "https://dummyimage.com/100x100/000/fff.png", keyword: "a"))

      visit root_path
      fill_in "username", with: user.username
      fill_in "password", with: 'known'
      click_button "Log in"
    end

    scenario "Recently Updated" do
      board = Timecop.freeze(desired_time) { create(:board, name: 'Testing Area', creator: user) }
      post1 = Timecop.freeze(desired_time - 1.minute) { create(:post, user: user, board: board, subject: "test subject 1", num_replies: 24, id: 101) }
      post2 = Timecop.freeze(desired_time - 2.minutes) { create(:post, user: user, board: board, subject: "test subject 2", num_replies: 28) }
      3.upto(76) do |i|
        Timecop.freeze(desired_time - i.minutes) do
          create(:post, user: user, board: board, subject: "test subject #{i}")
        end
      end

      Timecop.freeze(desired_time) do
        post2.mark_read(user)
        visit post_path(post1)
        visit posts_path(page: 2)
        3.times do
          create(:reply, post: post1, user: user, content: "test content")
        end
        visit posts_path
      end
      page.find('a', :text => 'test subject 4').hover
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
        template = create(:template, user: user, name: "Blank")
        character = create(:character,
          user: user,
          name: 'Alice',
          template_name: 'Ice',
          template: template,
          screenname: 'infosec_problem',
          settings: [create(:setting, name: "Testing Area"), create(:setting, name: "Crypto Problems")],
          pb: "Tester",
          gallery_groups: [create(:gallery_group, name: "Alice"), create(:gallery_group, name: "Eve")],
          description: "test content",
        )
        gallery = create(:gallery, user: user, name: "test gallery")
        icon = create(:icon, url: "https://dummyimage.com/100x100/000/fff.png&text=a", user: user, galleries: [gallery], keyword: 'a')
        create(:icon, url: "https://dummyimage.com/100x100/000/fff.png&text=b", user: user, galleries: [gallery], keyword: 'b')
        create(:icon, url: "https://dummyimage.com/100x100/000/fff.png&text=c", user: user, galleries: [gallery], keyword: 'c')
        character.update!(galleries: [gallery])
        character.update!(default_icon: icon)
        character.update!(aliases: [
          create(:alias, character: character, name: 'Alli'),
          create(:alias, character: character, name: 'Ice'),
          create(:alias, character: character, name: 'Eve'),
        ])
        visit edit_character_path(character)
      end
      expect(page).to match_expectation
    end

    scenario "Gallery" do
      1.upto(4) do |i|
        Timecop.freeze(desired_time + i.minutes) do
          create(:gallery_group, user: user, name: "Tag#{i}")
        end
      end
      Timecop.freeze(desired_time + 1.day) do
        gallery = create(:gallery, user: user, name: "test gallery", gallery_groups: GalleryGroup.all)
        gallery.icons = Array.new(10) do |i|
          create(:icon, url: "https://dummyimage.com/100x100/000/fff.png", user: user, keyword: i)
        end
        visit gallery_path(gallery)
      end
      page.find('a', :text => 'Tag1', match: :prefer_exact).hover
      expect(page).to match_expectation
    end

    context "with post" do
      let(:character1) { create(:character, name: "Alice", user: user) }
      let(:post) do
        warnings = Array.new(5) do |i|
          Timecop.freeze(desired_time + i.minutes) do
            create(:content_warning, name: "warning #{i+1}", user: user)
          end
        end
        settings = Array.new(2) do |i|
          Timecop.freeze(desired_time + i.minutes) do
            create(:setting, name: "test setting #{i+1}", user: user)
          end
        end
        labels = Array.new(3) do |i|
          Timecop.freeze(desired_time + i.minutes) do
            create(:label, name: "test tag #{i+1}", user: user)
          end
        end
        Timecop.freeze(desired_time + 1.day) do
          create(:post,
            user: user,
            character: character1,
            subject: 'Crypto Problems',
            description: "test subtitle",
            board: create(:board, name: 'Testing Area', id: 5),
            settings: settings,
            content_warnings: warnings,
            labels: labels,
            id: 80,
          )
        end
      end

      before(:each) do
        Timecop.freeze(desired_time) do
          character2 = create(:character, name: "Bob", user: other_user)
          1.upto(30) do |i|
            if i.odd?
              create(:reply, post: post, user: other_user, character: character2, content: "test content #{i}")
            elsif i.even?
              create(:reply, post: post, user: user, character: character1, content: "test content #{i}")
            end
          end
        end
      end

      scenario "Post" do
        Timecop.freeze(desired_time) do
          post.replies.find_by(reply_order: 25).update!(content:
            <<~HEREDOC
              <img src=https://dummyimage.com/400x200/000/fff>
              <hr/>
              <ul><li>list item a</li><li>list item b</li><li>list item c</li></ul>
            HEREDOC
          )
          post.replies.find_by(reply_order: 26).update!(content:
            <<~HEREDOC
              <table><tr><th>A</th><th>B</th><th>C</th></tr><tr><th>1</th><td>foo</td><td></td></tr><tr><th>2</th><td>bar</td><td>foobar</td></tr></table>
              <hr/>
              <ol><li>list item a</li><li>list item b</li><li>list item c</li></ol>
            HEREDOC
          )
          post.replies.find_by(reply_order: 27).update!(content:
            <<~HEREDOC
              <font style=\"font-variant: small-caps;\">behold the smallcaps test</font>
              <strong>bold with &lt;strong&gt;</strong>
              <b>bold with &lt;b&gt;</b>
              <em>italics with &lt;em&gt;</em>
              <i>italics with &lt;i&gt;</i>
              <var>italics with &lt;var&gt;</var>
              <u>underlined text</u>
              <strike>strikethrough with &lt;strike&gt;</strike>
              <s>strikethrough with &lt;s&gt;</s>
              <del>strikethrough with &lt;del&gt;</del>
              <small>en&lt;small&gt;ed text</small>
              <big>em&lt;big&gt;gened text</big>
              <mark>text highlighed with &lt;mark&gt;</mark>
              <samp>monospace text with &lt;samp&gt;</samp><h1>h1</h1><h2>h2</h2><h3>h3</h3><h4>h4</h4><h5>h5</h5><h6>h6</h6>H<sub>2</sub>0
              x<sup>2</sup>
              <abbr>Ms</abbr> Doe
              <a href="https://glowfic.com/">live constellation link</a>
              <a href="localhost:3000/posts/80?page=2">link to this thread</a>
              <cite>a citation</cite>
              <cite href="https://github.com/Marri/glowfic/">a citation with a link</cite>
              <quote>Most &lt;quote&gt;s on the internet are misattributed</quote>
              <kbd>kbd</kbd><pre>now you can      fancily     use whitespace with  &lt;pre&gt;</pre><details><summary>This is a &lt;summary&gt;</summary>These are the &lt;details&gt;</details>
              <details>These are more details, now without a summary</details>
              <details><summary>a new summary</summary> and more details</details>
            HEREDOC
          )
          post.replies.find_by(reply_order: 28).update!(content:
            <<~HEREDOC
              <blockquote>even blockquote</blockquote>
              <hr/>
              <dl><dt>test</dd><dd>noun. a procedure intended to establish the quality, performance, or reliability of something, especially before it is taken into widespread use.</dt> <dt>code</dd><dd>noun. program instructions</dt></dl>
            HEREDOC
          )
          post.replies.find_by(reply_order: 29).update!(content:
            <<~HEREDOC
              <blockquote cite="the Glowfic Constellation">odd blockquote</blockquote>
              <hr/>
              <code>Timecop.freeze(desired_time) do
                  visit post_path(post, page: 2)
                  sleep(0.5)
                end</code>
            HEREDOC
          )
          visit post_path(post, page: 2)
          sleep(0.5)
        end
        page.first('summary').click
        page.first('a', :text => /^1$/).hover
        expect(page).to match_expectation
      end

      scenario "Post#Edit" do
        Timecop.freeze(desired_time) do
          visit edit_post_path(post)
          sleep(0.5)
        end
        expect(page).to match_expectation
      end

      scenario "Post#Stats" do
        Timecop.freeze(desired_time) do
          character3 = create(:character, name: "Eve", user: user)
          create(:reply, post: post, user: user, character: character3, content: "test content")
          visit stats_post_path(post)
        end
        page.find('a', :text => 'test setting 1', match: :prefer_exact).hover
        expect(page).to match_expectation
      end

      scenario "Icon Picker" do
        user.update!(default_editor: 'html')
        Timecop.freeze(desired_time) do
          galleries = Array.new(3) do |i|
            gallery = create(:gallery, name: "test gallery", user: user)
            n = (i == 1) ? 9 : 3
            n.times do
              create(:icon, url: "https://dummyimage.com/100x100/000/fff.png", user: user, keyword: i, galleries: [gallery])
            end
            gallery
          end
          character1.update!(galleries: galleries)
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
