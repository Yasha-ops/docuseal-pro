# frozen_string_literal: true

class SmsSettingsController < ApplicationController
  before_action :load_encrypted_config
  authorize_resource :encrypted_config, only: :index
  authorize_resource :encrypted_config, parent: false, except: :index

  def index; end

  def create
    if @encrypted_config.update(sms_configs)
      redirect_to settings_sms_index_path, notice: I18n.t('changes_have_been_saved')
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
      EncryptedConfig.find_or_initialize_by(account: current_account, key: 'sms_configs')
  end

  def sms_configs
    params.require(:encrypted_config).permit(value: {}).tap do |e|
      e[:value].compact_blank!
    end
  end
end
