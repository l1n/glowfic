# frozen_string_literal: true
class ApplicationMailer < ActionMailer::Base
  default from: "Glowfic Constellation <#{ENV.fetch('GMAIL_USERNAME', nil)}>"
  helper :application
  helper :mailer
  layout 'mailer'

  def queue
    :mailer
  end

  private

  # Mail is rendered outside a request, so nothing has picked a language for it: use the
  # one the recipient reads the site in, and English when they haven't chosen one. The
  # subject line is built inside the block too, since it needs translating as well.
  def with_locale_for(user, &)
    I18n.with_locale(user&.ui_locale || Glowfic::Locales::DEFAULT, &)
  end
end
