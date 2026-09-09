# frozen_string_literal: true
module NotificationHelper
  # Wrapped in a method rather than a constant so the text is translated at the point of
  # use — a constant would freeze whichever language was current when the class loaded.
  def subject_for_type(notification_type)
    {
      'import_success'       => _("Post import succeeded"),
      'import_fail'          => _("Post import failed"),
      'new_favorite_post'    => _("An author you favorited has written a new post"),
      'joined_favorite_post' => _("An author you favorited has joined a post"),
    }[notification_type]
  end
end
