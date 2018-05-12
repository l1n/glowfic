require "spec_helper"

RSpec.describe User do
  describe "password encryption" do
    it "should support nil salt_uuid" do
      user = create(:user)
      user.update_columns(salt_uuid: nil, crypted: user.send(:old_crypted_password, 'test'))
      user.reload
      expect(user.authenticate('test')).to eq(true)
    end

    it "should set and support salt_uuid" do
      user = create(:user, password: 'test')
      expect(user.salt_uuid).not_to be_nil
      expect(user.authenticate('test')).to eq(true)
    end
  end

  it "should be unique by username" do
    user = create(:user, username: 'testuser1')
    new_user = build(:user, username: user.username.upcase)
    expect(new_user).not_to be_valid
  end

  describe "emails" do
    def generate_emailless_user
      user = build(:user, email: '')
      user.send(:encrypt_password)
      user.save!(validate: false)
      user
    end

    it "should be unique by email case-insensitively" do
      user = create(:user, email: 'testuser1@example.com')
      new_user = build(:user, email: user.email.upcase)
      expect(new_user).not_to be_valid
    end

    it "should require emails on new accounts" do
      user = build(:user, email: '')
      expect(user).not_to be_valid
      user.email = 'testuser@example.com'
      expect(user).to be_valid
    end

    it "should allow users with no email to be changed" do
      generate_emailless_user # to have duplicate without email
      user = generate_emailless_user
      user.layout = 'starrydark'
      expect(user).to be_valid
      expect {
        user.save!
      }.not_to raise_error
    end

    it "should allow users with no email to get an email" do
      generate_emailless_user # to have duplicate without email
      user = generate_emailless_user
      user.email = 'testuser@example.com'
      expect(user).to be_valid
      expect {
        user.save!
      }.not_to raise_error
    end
  end

  describe "moieties" do
    it "allows blank moieties" do
      user = build(:user, moiety: '')
      expect(user).to be_valid
    end

    it "rejects invalid sizes" do
      user1 = build(:user, moiety: '12')
      expect(user1).not_to be_valid

      user2 = build(:user, moiety: '1234')
      expect(user2).not_to be_valid

      user3 = build(:user, moiety: '1234567')
      expect(user3).not_to be_valid
    end

    it "rejects invalid characters" do
      user1 = build(:user, moiety: '12345Z')
      expect(user1).not_to be_valid

      user2 = build(:user, moiety: '123 456')
      expect(user2).not_to be_valid
    end

    it "allows short moieties" do
      user = build(:user, moiety: 'ABC')
      expect(user).to be_valid
    end

    it "allows long moieties" do
      user = build(:user, moiety: '123ABC')
      expect(user).to be_valid
    end

    it "allows lowercase" do
      user = build(:user, moiety: '123abc')
      expect(user).to be_valid
    end
  end

  it "orders galleryless icons" do
    user = create(:user)
    icon3 = create(:icon, user: user, keyword: "c")
    icon4 = create(:icon, user: user, keyword: "d")
    icon1 = create(:icon, user: user, keyword: "a")
    icon2 = create(:icon, user: user, keyword: "b")
    expect(user.galleryless_icons).to eq([icon1, icon2, icon3, icon4])
  end

  describe "archive" do
    it "succeeds" do
      user = create(:user)
      user.archive
      expect(user.deleted).to be(true)
    end

    it "turns off email notifications" do
      user = create(:user)
      user.update!(email_notifications: true)
      user.archive
      expect(user.deleted).to be(true)
      expect(user.email_notifications).to be(false)
    end

    it "removes ownership of settings" do
      user = create(:user)
      setting = create(:setting, user: user, owned: true)
      user.archive
      expect(user.deleted).to be(true)
      expect(setting.reload.owned).to be(false)
    end

    it "does not change username when persisted" do
      user = create(:user, username: 'test')
      user.archive
      user.reload
      expect(user.send(:[], :username)).to eq('test')
    end
  end
end
