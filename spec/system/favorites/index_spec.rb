RSpec.describe "Favorites page" do
  scenario "User views normal favorites" do
    user = create(:user, username: "usert")
    create(:post, user: user, subject: "user post") # user_post
    post = create(:post, subject: "postt")
    board = create(:board, creator: user, name: "boardt")
    create(:post, board: board, subject: "board post") # board_post
    create(:post, board: board, user: user, subject: "board user post") # board_user_post

    logged_in_user = login
    create(:favorite, user: logged_in_user, favorite: user)
    create(:favorite, user: logged_in_user, favorite: post)
    create(:favorite, user: logged_in_user, favorite: board)

    visit favorites_path

    expect(page).to have_text("Your Favorites")
    expect(page).to have_no_text("boardt Continuity")
    expect(page).to have_no_text("usert User")
    expect(page).to have_no_text("postt Post")
    expect(page).to have_text("user post")
    expect(page).to have_text("board post")
    expect(page).to have_text("board user post")

    click_link "Grouped »"

    expect(page).to have_text("Your Favorites")
    expect(page).to have_text("boardt Continuity")
    expect(page).to have_text("usert User")
    expect(page).to have_text("postt Post")
    expect(page).to have_no_text("user post")
    expect(page).to have_no_text("board post")
    expect(page).to have_no_text("board user post")
  end

  scenario "User sees links to individual pages of long threads" do
    logged_in_user = login
    logged_in_user.update!(per_page: 10)
    long_post = create(:post, subject: "long thread")
    create_list(:reply, 25, post: long_post, user: long_post.user)
    short_post = create(:post, subject: "short thread")
    create(:favorite, user: logged_in_user, favorite: long_post)
    create(:favorite, user: logged_in_user, favorite: short_post)

    visit favorites_path
    expect(page).to have_selector('.post-subject', count: 2)
    within('.post-subject', text: 'long thread') do
      expect(page).to have_link('1', href: post_path(long_post))
      expect(page).to have_link('2', href: post_path(long_post, page: 2))
      expect(page).to have_link('3', href: post_path(long_post, page: 3))
      expect(page).to have_no_link('4')
    end
    within('.post-subject', text: 'short thread') do
      expect(page).to have_no_link('1')
    end
  end
end
