require "spec_helper"

RSpec.describe IconMultiRemover do
  it "requires icons" do
    expect { IconMultiRemover.new({}) }.to raise_error(ApiError, "No icons selected.")
  end

  it "requires valid icons" do
    icon = create(:icon)
    icon.destroy!
    expect { IconMultiRemover.new({ marked_ids: [0, '0', 'abc', -1, '-1', icon.id] }) }.to raise_error(ApiError, "No icons selected.")
  end

  context "removing icons from a gallery" do
    let(:user) { create(:user) }

    it "requires gallery" do
      icon = create(:icon, user: user)
      deleter = IconMultiRemover.new({ marked_ids: [icon.id], gallery_delete: true })
      expect { deleter.perform(user) }.to raise_error(ApiError, "Gallery could not be found.")
    end

    it "requires your gallery" do
      icon = create(:icon, user: user)
      gallery = create(:gallery)
      deleter = IconMultiRemover.new({ marked_ids: [icon.id], gallery_id: gallery.id, gallery_delete: true })
      expect { deleter.perform(user) }.to raise_error(ApiError, "That is not your gallery.")
    end

    it "skips other people's icons" do
      icon = create(:icon)
      gallery = create(:gallery, user: user)
      gallery.icons << icon
      icon.reload
      expect(icon.galleries.count).to eq(1)
      deleter = IconMultiRemover.new({ marked_ids: [icon.id], gallery_id: gallery.id, gallery_delete: true })
      deleter.perform(user)
      icon.reload
      expect(icon.galleries.count).to eq(1)
    end

    it "removes int ids from gallery" do
      icon = create(:icon, user: user)
      gallery = create(:gallery, user: user)
      gallery.icons << icon
      expect(icon.galleries.count).to eq(1)
      deleter = IconMultiRemover.new({ marked_ids: [icon.id], gallery_id: gallery.id, gallery_delete: true })
      deleter.perform(user)
      expect(icon.galleries.count).to eq(0)
      expect(deleter.success_msg).to eq("Icons removed from gallery.")
    end

    it "removes string ids from gallery" do
      icon = create(:icon, user: user)
      gallery = create(:gallery, user: user)
      gallery.icons << icon
      expect(icon.galleries.count).to eq(1)
      deleter = IconMultiRemover.new({ marked_ids: [icon.id.to_s], gallery_id: gallery.id, gallery_delete: true })
      deleter.perform(user)
      expect(icon.galleries.count).to eq(0)
      expect(deleter.success_msg).to eq("Icons removed from gallery.")
    end
  end

  context "deleting icons from the site" do
    let(:user) { create(:user) }

    it "skips other people's icons" do
      icon = create(:icon)
      deleter = IconMultiRemover.new({ marked_ids: [icon.id] })
      deleter.perform(user)
      icon.reload
    end

    it "removes int ids from gallery" do
      icon = create(:icon, user: user)
      deleter = IconMultiRemover.new({ marked_ids: [icon.id] })
      deleter.perform(user)
      expect(Icon.find_by_id(icon.id)).to be_nil
    end

    it "removes string ids from gallery" do
      icon = create(:icon, user: user)
      icon2 = create(:icon, user: user)
      deleter = IconMultiRemover.new({ marked_ids: [icon.id.to_s, icon2.id.to_s] })
      deleter.perform(user)
      expect(Icon.find_by_id(icon.id)).to be_nil
      expect(Icon.find_by_id(icon2.id)).to be_nil
    end
  end
end
