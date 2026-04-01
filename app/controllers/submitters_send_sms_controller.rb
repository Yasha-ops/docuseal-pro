# frozen_string_literal: true

class SubmittersSendSmsController < ApplicationController
  load_and_authorize_resource :submitter, id_param: :submitter_slug, find_by: :slug

  def create
    return redirect_back(fallback_location: submission_path(@submitter.submission),
                         alert: 'No phone number for this recipient') if @submitter.phone.blank?

    config = EncryptedConfig.find_by(account: current_account, key: 'sms_configs')&.value

    return redirect_back(fallback_location: submission_path(@submitter.submission),
                         alert: 'SMS is not configured. Please set up SMS settings first.') if config.blank?

    SendSubmitterInvitationSmsJob.new.perform('submitter_id' => @submitter.id)

    redirect_back(fallback_location: submission_path(@submitter.submission), notice: 'SMS has been sent')
  rescue StandardError => e
    redirect_back(fallback_location: submission_path(@submitter.submission), alert: e.message)
  end
end
