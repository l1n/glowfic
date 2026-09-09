# frozen_string_literal: true
class UserMailer < ApplicationMailer
  helper WritableHelper
  helper IconHelper
  helper NotificationHelper
  include NotificationHelper

  def post_has_new_reply(user_id, reply_id)
    return unless (@reply = Reply.find_by(id: reply_id))

    @user = User.find_by(id: user_id)
    with_locale_for(@user) do
      @subject = format(_("New reply in the thread %{subject}"), subject: @reply.post.subject)
      mail(to: @user.email, subject: @subject)
    end
  end

  def password_reset_link(password_reset_id)
    @password_reset = PasswordReset.find(password_reset_id)
    with_locale_for(@password_reset.user) do
      @subject = _("Password Reset Link")
      mail(to: @password_reset.user.email, subject: @subject)
    end
  end

  def new_message(message_id)
    @message = Message.find(message_id)
    with_locale_for(@message.recipient) do
      @subject = format(_("New message from %{sender}: %{subject}"), sender: @message.sender_name, subject: @message.unempty_subject)
      mail(to: @message.recipient.email, subject: @subject)
    end
  end

  def new_notification(notification_id)
    @notification = Notification.find(notification_id)
    with_locale_for(@notification.user) do
      @subject = subject_for_type(@notification.notification_type)
      @subject += ": #{@notification.post.subject}" if @notification.post.present?
      @subject += ": #{@notification.error_msg}" if @notification.error_msg.present?
      mail(to: @notification.user.email, subject: @subject)
    end
  end
end
