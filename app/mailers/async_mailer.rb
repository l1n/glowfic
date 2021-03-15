class AsyncMailer < ApplicationMailer
  include Resque::Mailer

  default from: "Glowfic Constellation <#{ENV['GMAIL_USERNAME']}>"
  helper :application
  helper :mailer
  layout 'mailer'
end
