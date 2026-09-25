# Idempotent: safe to run in every environment, any number of times.

Setting.current

[
  [ "bug", "Something is broken or behaves wrongly.", "bug, broken, crash, error" ],
  [ "billing", "Charges, refunds, invoices, and subscriptions.", "billing, charge, refund, invoice" ],
  [ "feature request", "Asking for something the product does not do yet.", "feature request" ],
  [ "onboarding", "Getting started, setup, and first use.", "onboarding, setup" ],
  [ "praise", "Thanks, compliments, and happy stories.", "praise, thanks" ],
  [ "other", "Anything that fits no other category.", "other" ]
].each.with_index(1) do |(name, description, search_blurb), position|
  Category.find_or_create_by!(name: name) do |category|
    category.description = description
    category.search_blurb = search_blurb
    category.position = position
  end
end

# The dev login's people (development only; production signs in with Every).
if Rails.env.development?
  [ [ "dev@every.to", "Dev Person" ], [ "support@every.to", "Support Person" ] ].each do |email, name|
    User.find_or_create_by!(email_address: email) { |user| user.name = name }
  end
end
