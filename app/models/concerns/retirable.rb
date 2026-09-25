module Retirable
  extend ActiveSupport::Concern

  included do
    scope :active, -> { where(retired_at: nil) }
    scope :retired, -> { where.not(retired_at: nil) }
  end

  def retired?
    retired_at.present?
  end

  def retire!
    update!(retired_at: Time.current) unless retired?
  end

  def restore!
    update!(retired_at: nil)
  end
end
