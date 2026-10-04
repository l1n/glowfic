# frozen_string_literal: true
class SessionsController < ApplicationController
  # Actions that accept a same-origin request without a CSRF token.
  TOKENLESS_ACTIONS = ['create', 'confirm_tos'].freeze

  before_action :logout_required, only: [:new, :create, :confirm_tos]
  before_action :login_required, only: [:destroy]

  def index
  end

  def new
    @page_title = "Sign In"
  end

  def create
    auth = Authentication.new
    if auth.authenticate(params[:username], params[:password])
      user = auth.user
      flash[:success] = "You are now logged in as #{user.username}. Welcome back!"
      session[:user_id] = user.id
      session[:api_token] = {
        "value"   => auth.api_token,
        "expires" => Authentication::EXPIRY.from_now.to_i,
      }
      cookies.permanent.signed[:user_id] = cookie_hash(user.id) if params[:remember_me].present?
      @current_user = user
      redirect_to continuities_path and return if return_path == '/login'
    else
      flash[:error] = auth.error
    end
    redirect_to return_path # allow_other_host: false
  end

  def confirm_tos
    cookies.permanent[:accepted_tos] = cookie_hash(User::CURRENT_TOS_VERSION)
    redirect_to return_path # allow_other_host: false
  end

  def destroy
    url = return_path
    logout
    flash[:success] = "You have been logged out."
    redirect_to url # allow_other_host: false
  end

  private

  # The login and ToS forms appear on pages a shared cache may hold, and such a
  # page carries no CSRF token, because making one writes the session. For
  # these two actions a request from this site is accepted in place of a token.
  # Forgery protection stays on: anything else still needs a valid token, and a
  # failure goes through the usual InvalidAuthenticityToken handling.
  def verified_request?
    super || (TOKENLESS_ACTIONS.include?(action_name) && same_origin_request?)
  end

  # Blocks a form on another site from logging the reader in to an account of
  # its choosing, or from accepting the ToS for them. Browsers send
  # Sec-Fetch-Site on every request (Safari since 16.4, Chrome since 76,
  # Firefox since 90); older ones send Origin on a POST. A request with
  # neither header is not from a browser, so it is not a forged form.
  def same_origin_request?
    site = request.headers['Sec-Fetch-Site']
    return ['same-origin', 'none'].include?(site) if site.present?
    origin = request.headers['Origin']
    origin.blank? || origin == request.base_url
  end

  def cookie_hash(value)
    return { value: value, domain: 'glowfic-staging.herokuapp.com' } if request.host.include?('staging')
    return { value: value, domain: '.glowfic.com', tld_length: 2 } if Rails.env.production?
    { value: value }
  end
end
