# frozen_string_literal: true

class SamlController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :maybe_redirect_to_setup
  skip_authorization_check

  # GET /auth/saml — initiate SAML request, redirect to IdP
  def new
    config = saml_config
    return redirect_to new_user_session_path, alert: 'SSO is not configured.' if config.nil?

    settings = saml_settings(config)
    auth_request = OneLogin::RubySaml::Authrequest.new
    redirect_to auth_request.create(settings), allow_other_host: true
  end

  # POST /auth/saml/callback — receive and validate IdP assertion
  def create
    config = saml_config
    return redirect_to new_user_session_path, alert: 'SSO is not configured.' if config.nil?

    settings = saml_settings(config)
    response = OneLogin::RubySaml::Response.new(params[:SAMLResponse], settings:)
    response.settings = settings

    unless response.is_valid?
      Rails.logger.error("SAML validation failed: #{response.errors.join(', ')}")
      return redirect_to new_user_session_path, alert: "SSO authentication failed: #{response.errors.first}"
    end

    email = response.nameid.to_s.downcase.strip
    email = extract_email_from_attributes(response.attributes) if email.blank? || !email.include?('@')

    return redirect_to new_user_session_path, alert: 'Could not extract email from SSO response.' if email.blank?

    user = find_or_create_saml_user(email, response.attributes)
    return redirect_to new_user_session_path, alert: 'Your account is not authorized.' if user.nil?

    sign_in(:user, user)
    redirect_to root_path, notice: 'Signed in successfully via SSO.'
  end

  # GET /auth/saml/metadata — SP metadata XML for IdP configuration
  def metadata
    config = saml_config
    return head :not_found if config.nil?

    settings = saml_settings(config)
    meta = OneLogin::RubySaml::Metadata.new
    render xml: meta.generate(settings, true), content_type: 'application/xml'
  end

  private

  def saml_config
    # In self-hosted mode there is one account — find the first one
    account = Account.first
    return nil if account.nil?

    EncryptedConfig.find_by(account:, key: 'saml_configs')&.value.presence
  end

  def saml_settings(config)
    settings = OneLogin::RubySaml::Settings.new

    settings.assertion_consumer_service_url = "#{request.base_url}/auth/saml/callback"
    settings.sp_entity_id = config['sp_entity_id'].presence || request.base_url
    settings.idp_sso_target_url = config['idp_sso_target_url']
    settings.idp_entity_id = config['idp_entity_id']
    settings.idp_cert = config['idp_cert'].to_s.strip
    settings.name_identifier_format = config['name_identifier_format'].presence ||
                                      'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'

    settings.security[:authn_requests_signed]   = false
    settings.security[:want_assertions_signed]  = false
    settings.security[:digest_method]           = XMLSecurity::Document::SHA256
    settings.security[:signature_method]        = XMLSecurity::Document::RSA_SHA256

    settings
  end

  def extract_email_from_attributes(attributes)
    %w[email mail emailAddress http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress
       urn:oid:0.9.2342.19200300.100.1.3].each do |key|
      val = attributes[key]&.first.to_s.downcase.strip
      return val if val.include?('@')
    end
    nil
  end

  def find_or_create_saml_user(email, attributes)
    account = Account.first
    return nil if account.nil?

    user = User.find_by(account:, email:)

    if user.nil?
      first_name = attributes['firstName']&.first ||
                   attributes['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname']&.first || ''
      last_name  = attributes['lastName']&.first ||
                   attributes['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname']&.first || ''
      full_name  = [first_name, last_name].join(' ').strip
      full_name  = email.split('@').first if full_name.blank?

      user = User.new(
        account:,
        email:,
        first_name: first_name.presence || full_name,
        last_name: last_name.presence,
        role: User::ADMIN_ROLE,
        password: SecureRandom.hex(32)
      )
      user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
      user.save!
    end

    user
  end
end
