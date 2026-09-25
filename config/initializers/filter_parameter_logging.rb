# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# Customer message content arrives as webhook parameters (Slack text, Intercom
# body, Postmark TextBody/HtmlBody/StrippedTextReply/Subject/Attachments, custom
# webhook body) and must not reach the request log. Matching is partial and
# case-insensitive.
Rails.application.config.filter_parameters += [
  :body, :text, :subject, :attachments
]
