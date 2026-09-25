defmodule NightShift.Repo.Migrations.RelaxMessageBodyCheck do
  use Ecto.Migration

  # The 1..2000 limit of criterion 6 is measured in graphemes, and Postgres
  # cannot count those: `char_length` counts codepoints, so 2000 grapheme
  # clusters of "e" + a combining accent are 4000 characters and the original
  # check refused a legal message. No fixed codepoint ceiling can stand in for a
  # grapheme one either, since a single grapheme may carry arbitrarily many
  # combining codepoints.
  #
  # The database therefore keeps only what it can state exactly — a message is
  # not empty once trimmed — and `NightShift.Chat.Message.create_changeset/4`
  # owns the upper bound.
  def up do
    drop constraint(:messages, :body_length)

    create constraint(:messages, :body_not_empty, check: "char_length(btrim(body)) >= 1")
  end

  def down do
    drop constraint(:messages, :body_not_empty)

    create constraint(:messages, :body_length, check: "char_length(body) BETWEEN 1 AND 2000")
  end
end
