# Idempotent: safe to run in every environment, any number of times.

Setting.current

[
  [ "bug", "Something is broken or behaves wrongly." ],
  [ "billing", "Charges, refunds, invoices, and subscriptions." ],
  [ "feature request", "Asking for something the product does not do yet." ],
  [ "onboarding", "Getting started, setup, and first use." ],
  [ "praise", "Thanks, compliments, and happy stories." ],
  [ "other", "Anything that fits no other category." ]
].each.with_index(1) do |(name, description), position|
  Category.find_or_create_by!(name: name) do |category|
    category.description = description
    category.position = position
  end
end
