module ApplicationHelper
  def icon_tag(icon, **args)
    return '' if icon.nil?

    klass = 'icon'
    klass += ' pointer' if args.delete(:pointer)
    image_tag icon.url, {alt: icon.keyword, title: icon.keyword, class: klass}.merge(**args)
  end

  def no_icon_tag(**args)
    klass = 'icon'
    klass += ' pointer' if args.delete(:pointer)
    image_tag "/images/no-icon.png", {class: klass, alt:'No Icon', title: 'No Icon'}.merge(**args)
  end

  def pretty_time(time)
    return unless time
    time_display = "%b %d, %Y %l:%M %p"
    time_display = current_user.time_display if current_user
    time.strftime(time_display)
  end

  def fun_name(user)
    return user.username unless user.moiety
    content_tag :span, user.username, style: 'font-weight: bold; color: #' + user.moiety
  end

  def color_block(user)
    return unless user.moiety
    content_tag :span, '⬤', style: 'cursor: default; color: #' + user.moiety, title: user.moiety_name
  end

  def path_for(obj, path)
    send (path + '_path') % obj.class.to_s.downcase, obj
  end

  def per_page_options(default=nil)
    default ||= per_page
    options = [10,25,50,100,250,500]
    options << default unless default.nil? || default.zero? || options.include?(default)
    options = Hash[*(options * 2).sort].merge({'All' => 'all'})
    default = 'all' if default == -1
    options_for_select(options, default)
  end

  def timezone_options(default=nil)
    default ||= 'Eastern Time (US & Canada)'
    zones = ActiveSupport::TimeZone.all()
    options_from_collection_for_select(zones, :name, :to_s, default)
  end

  def layout_options(default=nil)
    layouts = {
      Default: nil,
      Dark: 'dark',
      Iconless: 'iconless',
      Starry: 'starry',
      :"Starry Dark" => 'starrydark',
      :"Starry Light" => 'starrylight',
      Monochrome: 'monochrome',
      :"Milky River" => 'river',
    }
    options_for_select(layouts, default)
  end
  
  def time_display_options(default=nil)
    now = Time.now
    time_thing = Time.new(2016, 12, 25, 21, 34)
    time_display_list = ["%b %d, %Y %l:%M %p", "%b %d, %Y %H:%M",
      "%d %b %Y %l:%M %p", "%d %b %Y %H:%M",
      "%m-%d-%Y %l:%M %p", "%m-%d-%Y %H:%M",
      "%d-%m-%Y %l:%M %p", "%d-%m-%Y %H:%M",
      "%Y-%m-%d %l:%M %p", "%Y-%m-%d %H:%M"]
    time_displays = {}
    time_display_list.each do |time_display|
      time_displays[time_thing.strftime(time_display)] = time_display
    end
    options_for_select(time_displays, default)
  end

  def post_or_reply_link(reply)
    return unless reply.id.present?
    if reply.is_a?(Reply)
      reply_path(reply, anchor: "reply-#{reply.id}")
    else
      post_path(reply)
    end
  end
end
