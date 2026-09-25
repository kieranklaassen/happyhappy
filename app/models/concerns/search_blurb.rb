# The few words feed search matches a query against for a product or category
# ("Cora assistant"), apart from the description and hint words the classifier
# reads. Defaults to the name. Keep it free of words people search for as text
# ("email", "inbox"): once the option is applied, those words stop matching.
module SearchBlurb
  extend ActiveSupport::Concern

  MAX_LENGTH = 40

  included do
    normalizes :search_blurb, with: ->(blurb) { blurb.squish.presence }

    before_validation -> { self.search_blurb = name.to_s.first(MAX_LENGTH) }, if: -> { search_blurb.blank? }

    validates :search_blurb, length: { maximum: MAX_LENGTH }
  end
end
