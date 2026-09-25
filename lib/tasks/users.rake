# frozen_string_literal: true

namespace :users do
  desc "Pre-provision an every.to person ahead of their first Sign in with Every " \
       "(there is no open registration). Usage: EMAIL=ana@every.to NAME='Ana' bin/rails users:create"
  task create: :environment do
    email = ENV["EMAIL"].presence
    abort "EMAIL is required (EMAIL=you@every.to bin/rails users:create)" if email.nil?
    abort "EMAIL must be an @#{User::EVERY_EMAIL_DOMAIN} address" unless User.every_email?(email)

    user = User.create!(email_address: email, name: ENV["NAME"].presence)
    puts "Created user #{user.email_address} (##{user.id})"
  rescue ActiveRecord::RecordInvalid => e
    abort "Could not create user: #{e.record.errors.full_messages.to_sentence}"
  end
end
