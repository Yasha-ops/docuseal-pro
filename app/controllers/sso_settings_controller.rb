# frozen_string_literal: true

class SsoSettingsController < ApplicationController
  before_action :load_encrypted_config
  authorize_resource :encrypted_config, only: :index
  authorize_resource :encrypted_config, parent: false, only: :create

  def index; end

  def create
    if @encrypted_config.update(sso_configs)
      @force_sso_config = AccountConfig.find_or_initialize_by(
        account: current_account,
        key: AccountConfig::FORCE_SSO_AUTH_KEY
      )
      @force_sso_config.update(value: params.dig(:account_config, :force_sso).present?)

      redirect_to settings_sso_index_path, notice: I18n.t('changes_have_been_saved')
    else
      render :index, status: :unprocessable_content
    end
  rescue StandardError => e
    flash[:alert] = e.message
    render :index, status: :unprocessable_content
  end

  private

  def load_encrypted_config
    @encrypted_config =
      EncryptedConfig.find_or_initialize_by(account: current_account, key: 'saml_configs')
  end

  def sso_configs
    params.require(:encrypted_config).permit(value: {}).tap do |e|
      e[:value].compact_blank!
    end
  end
end
