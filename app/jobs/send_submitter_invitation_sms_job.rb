# frozen_string_literal: true

class SendSubmitterInvitationSmsJob
  include Sidekiq::Job

  DEFAULT_TEMPLATE = 'Please sign the document: {{link}}'

  def perform(params = {})
    submitter = Submitter.find(params['submitter_id'])

    return if submitter.completed_at?
    return if submitter.phone.blank?
    return if submitter.submission.archived_at?
    return if submitter.template&.archived_at?

    config = EncryptedConfig.find_by(account: submitter.account, key: 'sms_configs')&.value
    return if config.blank?

    sign_url = Rails.application.routes.url_helpers.submit_form_url(
      slug: submitter.slug,
      **Docuseal.default_url_options
    )

    template = config['message_template'].presence || DEFAULT_TEMPLATE
    message = template.gsub('{{link}}', sign_url).gsub('{{name}}', submitter.name.to_s)

    case config['provider']
    when 'twilio'
      send_via_twilio(config, submitter.phone, message)
    when 'vonage'
      send_via_vonage(config, submitter.phone, message)
    when 'brevo'
      send_via_brevo(config, submitter.phone, message)
    else
      Rails.logger.warn("SMS provider '#{config['provider']}' not supported")
      return
    end

    SubmissionEvent.create!(submitter:, event_type: 'send_sms')

    submitter.sent_at ||= Time.current
    submitter.save!
  end

  private

  def send_via_twilio(config, to, message)
    require 'net/http'
    require 'uri'

    uri = URI("https://api.twilio.com/2010-04-01/Accounts/#{config['twilio_account_sid']}/Messages.json")
    req = Net::HTTP::Post.new(uri)
    req.basic_auth(config['twilio_account_sid'], config['twilio_auth_token'])
    req.set_form_data('To' => to, 'From' => config['twilio_phone_number'], 'Body' => message)

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    raise "Twilio error: #{res.body}" unless res.is_a?(Net::HTTPSuccess)
  end

  def send_via_vonage(config, to, message)
    require 'net/http'
    require 'uri'
    require 'json'

    uri = URI('https://rest.nexmo.com/sms/json')
    req = Net::HTTP::Post.new(uri)
    req['Content-Type'] = 'application/json'
    req.body = {
      api_key: config['vonage_api_key'],
      api_secret: config['vonage_api_secret'],
      to: to.gsub(/\A\+/, ''),
      from: config['vonage_from'].presence || 'DocuSeal',
      text: message
    }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    body = JSON.parse(res.body)
    raise "Vonage error: #{body}" if body.dig('messages', 0, 'status') != '0'
  end

  def send_via_brevo(config, to, message)
    require 'net/http'
    require 'uri'
    require 'json'

    uri = URI('https://api.brevo.com/v3/transactionalSMS/sms')
    req = Net::HTTP::Post.new(uri)
    req['api-key'] = config['brevo_api_key']
    req['Content-Type'] = 'application/json'
    req.body = {
      sender: config['brevo_sender'].presence || 'DocuSeal',
      recipient: to.gsub(/\A\+/, ''),
      content: message
    }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    raise "Brevo error: #{res.body}" unless res.is_a?(Net::HTTPSuccess)
  end
end
