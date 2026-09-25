# The classifier kept filing Every's other events under the Thesis conference.
# Only descriptions nobody has edited since are updated, so admin changes stand.
class NarrowThesisProductDescription < ActiveRecord::Migration[8.1]
  CHANGES = {
    "thesis-2027" => [
      "Every's first annual AI conference (Brooklyn, November 5, 2026), including tickets, applications, and Thesis Statements.",
      "Only Thesis: 2027, Every's first annual AI conference (Brooklyn, November 5, 2026): its tickets, applications, " \
        "speakers, and Thesis Statements. Other Every events, camps, meetups, and calls belong to Every."
    ],
    "every" => [
      "Every's paid subscription and daily AI newsletter: essays, columns (Chain of Thought, Context Window, Vibe Check), " \
        "the AI & I podcast, the All Access plan, the Builder Pack, and the every.to account itself.",
      "Every's paid subscription and daily AI newsletter: essays, columns (Chain of Thought, Context Window, Vibe Check), " \
        "the AI & I podcast, the All Access plan, the Builder Pack, and the every.to account itself, and Every's other " \
        "events, camps, meetups, and calls."
    ]
  }.freeze

  def up
    CHANGES.each { |slug, (from, to)| update(slug, from, to) }
  end

  def down
    CHANGES.each { |slug, (from, to)| update(slug, to, from) }
  end

  private

  def update(slug, from, to)
    execute(sanitize_sql([ "UPDATE products SET description = ? WHERE slug = ? AND description = ?", to, slug, from ]))
  end

  def sanitize_sql(args)
    ActiveRecord::Base.sanitize_sql_array(args)
  end
end
