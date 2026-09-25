# Classification seam (KTD9). A classifier responds to `call(message)` and returns
# TypeSafe's parsed answers hash for one message, keyed by question id:
#
#   "relevant"  => { "type" => "noul", "noul" => 0.93 }
#   "product"   => { "type" => "choice", "choice" => "cora", "probabilities" => { ... }, "confidence" => 0.8 }
#   "category"  => { "type" => "choice", "choice" => "bug", ... }
#   "sentiment" => { "type" => "choice", "choice" => "complaint", ... }
#   "anger"     => { "type" => "noul", "noul" => 0.85 }
#   "team_author" => { "type" => "noul", "noul" => 0.1 }  # only when the author is unknown
#
# Production resolves Classification::Classifier; tests swap in FakeClassifier.
module Classification
  DEFAULT_CLASSIFIER = "Classification::Classifier"
  # Stamped on each message it classifies; bump it when the questions or the
  # state change so `rake classifications:rerun` knows what is stale.
  VERSION = "2026-09-25.1"

  class << self
    attr_writer :classifier

    def classifier
      @classifier || DEFAULT_CLASSIFIER.constantize.new
    end
  end
end
