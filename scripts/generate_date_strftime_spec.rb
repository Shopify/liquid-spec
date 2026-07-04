#!/usr/bin/env ruby
# frozen_string_literal: true
# Generates the exhaustive date/time strftime spec YAML from liquid-ruby.
# Deliberately does NOT set ENV["TZ"]: every timezone-sensitive directive is
# given an input that carries its own zone, so the output is identical under
# any ambient timezone. Time is frozen to 2024-01-01 00:01:58 UTC (a Time.utc
# object). Every expected value below is the actual liquid-ruby output, so
# the spec is self-verifying against the reference.
#
# Usage:  ruby scripts/generate_date_strftime_spec.rb > specs/basics/date-strftime.yml

require "liquid"
require "time"

# Deliberately NOT setting ENV["TZ"]. These specs avoid depending on the
# ambient timezone: every timezone-sensitive directive (%z %Z %:z %::z %s)
# is given an input that carries its own zone (explicit "UTC" suffix or a
# numeric offset), so the expected output is identical under any ENV["TZ"].
# Wall-clock directives (%Y %m %d %H %M %S %B %A %j %p ...) are parsed as
# written and are also TZ-independent. The frozen 'now' is a Time.utc object,
# so its %z/%Z are TZ-independent too.
TEST_TIME = Time.utc(2024, 1, 1, 0, 1, 58)

class << Time
  alias_method :__now__, :now
  def now; $frozen_time || __now__; end
end
$frozen_time = TEST_TIME

def r(template)
  Liquid::Template.parse(template).render
end

def lit(s)
  s.to_s.gsub("\\", "\\\\\\\\").gsub("'", "\\\\'")
end

specs = []
counter = 0

def add(specs, name, template, expected, complexity, hint)
  specs << { name: name, template: template, expected: expected,
             complexity: complexity, hint: hint }
end

MONTHS = %w[January February March April May June July August September October November December]
MONTHS_A = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]
WD = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]
WD_A = %w[Sun Mon Tue Wed Thu Fri Sat]

# ============================================================
# SECTION 1: every month, full directive set
# ============================================================
(1..12).each do |m|
  date = format("2020-%02d-15", m)   # 15th of each month in 2020 (leap year)
  idx = m - 1
  add(specs, "date_month_#{m.to_s.rjust(2,'0')}_B_full",
      "{{ '#{date}' | date: '%B' }}",
      r("{{ '#{date}' | date: '%B' }}"), 105,
      "%B outputs the full month name (#{MONTHS[idx]}).")
  add(specs, "date_month_#{m.to_s.rjust(2,'0')}_b_abbr",
      "{{ '#{date}' | date: '%b' }}",
      r("{{ '#{date}' | date: '%b' }}"), 105,
      "%b outputs the abbreviated month name (#{MONTHS_A[idx]}).")
  add(specs, "date_month_#{m.to_s.rjust(2,'0')}_h_abbr_alias",
      "{{ '#{date}' | date: '%h' }}",
      r("{{ '#{date}' | date: '%h' }}"), 105,
      "%h is an alias for %b (abbreviated month name, #{MONTHS_A[idx]}).")
  add(specs, "date_month_#{m.to_s.rjust(2,'0')}_m_padded",
      "{{ '#{date}' | date: '%m' }}",
      r("{{ '#{date}' | date: '%m' }}"), 105,
      "%m outputs the month as a zero-padded decimal (#{format('%02d', m)}).")
  add(specs, "date_month_#{m.to_s.rjust(2,'0')}_m_unpadded",
      "{{ '#{date}' | date: '%-m' }}",
      r("{{ '#{date}' | date: '%-m' }}"), 140,
      "%-m removes zero padding for the month number (#{m}).")
  add(specs, "date_month_#{m.to_s.rjust(2,'0')}_B_upper",
      "{{ '#{date}' | date: '%^B' }}",
      r("{{ '#{date}' | date: '%^B' }}"), 145,
      "%^B uppercases the full month name (#{MONTHS[idx].upcase}).")
  add(specs, "date_month_#{m.to_s.rjust(2,'0')}_b_upper",
      "{{ '#{date}' | date: '%^b' }}",
      r("{{ '#{date}' | date: '%^b' }}"), 145,
      "%^b uppercases the abbreviated month name (#{MONTHS_A[idx].upcase}).")
end

# ============================================================
# SECTION 2: every weekday, full directive set
# ============================================================
# 2020-06-14=Sun, 15=Mon, ... 20=Sat
(0..6).each do |w|
  day = 14 + w
  date = "2020-06-#{format('%02d', day)}"
  u = (w == 0 ? 7 : w)   # %u: Mon=1..Sun=7
  add(specs, "date_weekday_#{w}_A_full",
      "{{ '#{date}' | date: '%A' }}",
      r("{{ '#{date}' | date: '%A' }}"), 125,
      "%A outputs the full weekday name (#{WD[w]}). 2020-06-#{day} is a #{WD[w]}.")
  add(specs, "date_weekday_#{w}_a_abbr",
      "{{ '#{date}' | date: '%a' }}",
      r("{{ '#{date}' | date: '%a' }}"), 125,
      "%a outputs the abbreviated weekday name (#{WD_A[w]}).")
  add(specs, "date_weekday_#{w}_w_sunday_zero",
      "{{ '#{date}' | date: '%w' }}",
      r("{{ '#{date}' | date: '%w' }}"), 130,
      "%w outputs the weekday with Sunday=0 (#{w}).")
  add(specs, "date_weekday_#{w}_u_monday_one",
      "{{ '#{date}' | date: '%u' }}",
      r("{{ '#{date}' | date: '%u' }}"), 130,
      "%u outputs the weekday with Monday=1, Sunday=7 (#{u}).")
  add(specs, "date_weekday_#{w}_A_upper",
      "{{ '#{date}' | date: '%^A' }}",
      r("{{ '#{date}' | date: '%^A' }}"), 145,
      "%^A uppercases the full weekday name (#{WD[w].upcase}).")
  add(specs, "date_weekday_#{w}_a_upper",
      "{{ '#{date}' | date: '%^a' }}",
      r("{{ '#{date}' | date: '%^a' }}"), 145,
      "%^a uppercases the abbreviated weekday name (#{WD_A[w].upcase}).")
end

# ============================================================
# SECTION 3: every single strftime directive on a fixed datetime
# Fixed: 2020-06-15 14:30:45 (Monday). Timezone-sensitive ones use UTC input.
# ============================================================
DT   = "2020-06-15 14:30:45"          # bare; only used for TZ-independent (wall-clock) directives
DTU  = "2020-06-15 14:30:45 UTC"      # explicit UTC -> used for %z %Z %:z %::z
DTS  = "2020-06-15 12:00:00 UTC"      # explicit UTC -> for %s (deterministic epoch)
DTMS = "2020-06-15 14:30:45.123456"   # for fractional second directives

# [directive, input, complexity, hint]
dir_table = [
  ["%A", DT,  125, "%A full weekday name (Monday)."],
  ["%a", DT,  125, "%a abbreviated weekday name (Mon)."],
  ["%B", DT,  105, "%B full month name (June)."],
  ["%b", DT,  105, "%b abbreviated month name (Jun)."],
  ["%h", DT,  105, "%h alias for %b (Jun)."],
  ["%C", DT,  110, "%C century (year/100, zero-padded to 2 digits)."],
  ["%c", DT,  165, "%c locale's preferred date+time; C locale: 'Mon Jun 15 14:30:45 2020'."],
  ["%d", DT,  120, "%d day of month, zero-padded (01..31)."],
  ["%D", DT,  165, "%D short date, equivalent to %m/%d/%y."],
  ["%e", DT,  120, "%e day of month, space-padded ( 1..31)."],
  ["%F", DT,  165, "%F ISO 8601 date, equivalent to %Y-%m-%d."],
  ["%G", "2019-12-30", 155, "%G ISO 8601 week-based year (Dec 30 2019 -> 2020)."],
  ["%g", "2019-12-30", 155, "%g 2-digit ISO week-based year (Dec 30 2019 -> 20)."],
  ["%H", DT,  130, "%H hour, 24-hour, zero-padded (00..23)."],
  ["%I", DT,  135, "%I hour, 12-hour, zero-padded (01..12)."],
  ["%j", "2020-03-01", 125, "%j day of year, zero-padded to 3 digits (001..366)."],
  ["%k", "2020-06-15 09:30:00", 140, "%k hour 24-hour, space-padded."],
  ["%l", "2020-06-15 09:30:00", 140, "%l hour 12-hour, space-padded."],
  ["%L", DTMS, 150, "%L millisecond of the second, zero-padded to 3 digits."],
  ["%M", DT,  135, "%M minute, zero-padded (00..59)."],
  ["%m", DT,  110, "%m month, zero-padded (01..12)."],
  ["%N", DTMS, 155, "%N fractional seconds digits (default 9 digits: nanoseconds)."],
  ["%n", DT,  160, "%n a newline character."],
  ["%p", DT,  140, "%p meridian indicator uppercase AM/PM."],
  ["%P", DT,  140, "%P meridian indicator lowercase am/pm."],
  ["%R", DT,  165, "%R time, equivalent to %H:%M."],
  ["%r", DT,  170, "%r 12-hour time with AM/PM, equivalent to %I:%M:%S %p."],
  ["%S", DT,  135, "%S second, zero-padded (00..60)."],
  ["%s", DTS, 145, "%s Unix timestamp (seconds since 1970-01-01 UTC)."],
  ["%t", DT,  160, "%t a tab character."],
  ["%T", DT,  165, "%T 24-hour time with seconds, equivalent to %H:%M:%S."],
  ["%U", "2020-01-05", 145, "%U week number, Sunday as first day (00..53)."],
  ["%u", DT,  130, "%u weekday, Monday=1..7."],
  ["%V", "2020-01-01", 150, "%V ISO 8601 week number (01..53)."],
  ["%W", "2020-01-06", 145, "%W week number, Monday as first day (00..53)."],
  ["%w", DT,  130, "%w weekday, Sunday=0..6."],
  ["%X", DT,  165, "%X locale's preferred time; C locale: '14:30:45'."],
  ["%x", DT,  165, "%x locale's preferred date; C locale: '06/15/20'."],
  ["%Y", DT,  105, "%Y year with century."],
  ["%y", DT,  105, "%y 2-digit year (00..99)."],
  ["%Z", DTU, 160, "%Z timezone name/abbreviation. For explicit UTC -> 'UTC'."],
  ["%z", "2020-06-15 14:30:45 -0400", 150, "%z timezone offset from UTC (+/-HHMM)."],
  ["%%", DT,  155, "%% a literal percent sign."],
]

dir_table.each do |d, input, c, hint|
  tmpl = "{{ '#{lit(input)}' | date: '#{d}' }}"
  out = r(tmpl)
  key = "date_dir_#{d.sub('%','pct_').gsub(/[^a-zA-Z0-9]/,'_')}"
  add(specs, key, tmpl, out, c, hint)
end

# ============================================================
# SECTION 4: timezone coverage
# Inputs across named + numeric offsets, testing %z %:z %::z %Z %s.
# ============================================================
tz_inputs = [
  ["2020-06-15 14:30:45 UTC",      "named UTC"],
  ["2020-06-15 14:30:45 +0000",    "numeric +0000"],
  ["2020-06-15 14:30:45 -0400",    "numeric -0400 (Eastern)"],
  ["2020-06-15 14:30:45 -04:00",   "offset with colon -04:00"],
  ["2020-06-15 14:30:45 +0530",    "numeric +0530 (India)"],
  ["2020-06-15 14:30:45 +05:30",   "offset with colon +05:30"],
  ["2020-06-15 14:30:45 +0900",    "numeric +0900 (Japan)"],
  ["2020-06-15 14:30:45 +09:00",   "offset with colon +09:00"],
  ["2020-06-15 14:30:45 -0800",    "numeric -0800 (Pacific)"],
  ["2020-06-15 14:30:45 -08:00",   "offset with colon -08:00"],
]

tz_inputs.each_with_index do |(input, label), i|
  base = "date_tz_#{i}"
  # %z numeric offset
  add(specs, "#{base}_z",
      "{{ '#{lit(input)}' | date: '%z' }}",
      r("{{ '#{lit(input)}' | date: '%z' }}"), 150,
      "%z for #{label}: signed numeric offset HHMM.")
  # %:z offset with colon
  add(specs, "#{base}_colon_z",
      "{{ '#{lit(input)}' | date: '%:z' }}",
      r("{{ '#{lit(input)}' | date: '%:z' }}"), 155,
      "%:z for #{label}: offset with a colon (HH:MM).")
  # %::z offset with colons HH:MM:SS
  add(specs, "#{base}_coloncolon_z",
      "{{ '#{lit(input)}' | date: '%::z' }}",
      r("{{ '#{lit(input)}' | date: '%::z' }}"), 158,
      "%::z for #{label}: offset with colons (HH:MM:SS).")
  # %Z zone name (often empty for numeric-only offsets).
  # Skip for the bare +0000 numeric offset: Ruby substitutes the ambient
  # ENV["TZ"] zone name there (e.g. "UTC"/"America"/"Asia"), so it is not
  # TZ-independent. Non-zero offsets deterministically yield ""; the named
  # UTC input deterministically yields "UTC".
  unless input.end_with?("+0000")
    add(specs, "#{base}_Z",
        "{{ '#{lit(input)}' | date: '%Z' }}",
        r("{{ '#{lit(input)}' | date: '%Z' }}"), 160,
        "%Z for #{label}: timezone name; numeric-only offsets have no named zone, so expect empty.")
  end
  # %s epoch seconds reflect the offset (offset shifts the instant)
  add(specs, "#{base}_s",
      "{{ '#{lit(input)}' | date: '%s' }}",
      r("{{ '#{lit(input)}' | date: '%s' }}"), 145,
      "%s for #{label}: epoch seconds depend on the parsed offset.")
end

# ============================================================
# SECTION 5: hour edge cases (midnight / noon) for 12h & 24h
# ============================================================
[
  ["2020-06-15 00:30:00", "midnight",  "00", "12", "AM", "am", " 0", "12"],
  ["2020-06-15 12:00:00", "noon",      "12", "12", "PM", "pm", "12", "12"],
  ["2020-06-15 09:30:00", "morning",   "09", "09", "AM", "am", " 9", " 9"],
  ["2020-06-15 14:30:00", "afternoon", "14", "02", "PM", "pm", "14", " 2"],
  ["2020-06-15 23:59:59", "last_hour", "23", "11", "PM", "pm", "23", "11"],
].each do |input, label, h24, h12, pmu, pml, k, l|
  base = "date_hour_#{label}"
  add(specs, "#{base}_H", "{{ '#{input}' | date: '%H' }}",
      r("{{ '#{input}' | date: '%H' }}"), 130, "%H 24-hour zero-padded for #{label}.")
  add(specs, "#{base}_I", "{{ '#{input}' | date: '%I' }}",
      r("{{ '#{input}' | date: '%I' }}"), 135, "%I 12-hour zero-padded for #{label}.")
  add(specs, "#{base}_k", "{{ '#{input}' | date: '%k' }}",
      r("{{ '#{input}' | date: '%k' }}"), 140, "%k 24-hour space-padded for #{label}.")
  add(specs, "#{base}_l", "{{ '#{input}' | date: '%l' }}",
      r("{{ '#{input}' | date: '%l' }}"), 140, "%l 12-hour space-padded for #{label}.")
  add(specs, "#{base}_p", "{{ '#{input}' | date: '%p' }}",
      r("{{ '#{input}' | date: '%p' }}"), 140, "%p uppercase AM/PM for #{label}.")
  add(specs, "#{base}_P", "{{ '#{input}' | date: '%P' }}",
      r("{{ '#{input}' | date: '%P' }}"), 140, "%P lowercase am/pm for #{label}.")
end

# ============================================================
# SECTION 6: padding / case flags across directives
# ============================================================
# dash (no padding)
[["%-d", "2020-06-05", "190"], ["%-m", "2020-06-05", "190"],
 ["%-H", "2020-06-15 09:30:00", "190"], ["%-I", "2020-06-15 09:30:00", "190"],
 ["%-M", "2020-06-15 14:05:00", "190"], ["%-S", "2020-06-15 14:30:07", "190"],
 ["%-j", "2020-01-15", "190"], ["%-Y", "2020-06-15", "190"]].each do |d, input, c|
  add(specs, "date_flag_#{d.sub('%','pct_').gsub(/[^a-zA-Z0-9]/,'_')}_#{input.gsub(/[^0-9]/,'')}",
      "{{ '#{input}' | date: '#{d}' }}",
      r("{{ '#{input}' | date: '#{d}' }}"), c.to_i,
      "#{d} uses the '-' flag to strip zero padding.")
end
# underscore (space padding)
[["%_d", "2020-06-05"], ["%_m", "2020-06-05"],
 ["%_H", "2020-06-15 09:30:00"], ["%_I", "2020-06-15 09:30:00"],
 ["%_M", "2020-06-15 14:05:00"], ["%_S", "2020-06-15 14:30:07"]].each do |d, input|
  add(specs, "date_flag_#{d.sub('%','pct_').gsub(/[^a-zA-Z0-9]/,'_')}_#{input.gsub(/[^0-9]/,'')}",
      "{{ '#{input}' | date: '#{d}' }}",
      r("{{ '#{input}' | date: '#{d}' }}"), 190,
      "#{d} uses the '_' flag for space padding.")
end
# zero padding (explicit)
[["%0d", "2020-06-05"], ["%0m", "2020-06-05"],
 ["%0H", "2020-06-15 09:30:00"], ["%0Y", "2020-06-15"]].each do |d, input|
  add(specs, "date_flag_#{d.sub('%','pct_').gsub(/[^a-zA-Z0-9]/,'_')}_#{input.gsub(/[^0-9]/,'')}",
      "{{ '#{input}' | date: '#{d}' }}",
      r("{{ '#{input}' | date: '#{d}' }}"), 190,
      "#{d} uses the '0' flag for explicit zero padding.")
end
# caret (uppercase)
[["%^b", "2020-06-15"], ["%^B", "2020-06-15"],
 ["%^a", "2020-06-15"], ["%^A", "2020-06-15"],
 ["%^p", "2020-06-15 14:30:00"], ["%^P", "2020-06-15 14:30:00"]].each do |d, input|
  add(specs, "date_flag_#{d.sub('%','pct_').gsub(/[^a-zA-Z0-9]/,'_')}_#{input.gsub(/[^0-9]/,'')}",
      "{{ '#{input}' | date: '#{d}' }}",
      r("{{ '#{input}' | date: '#{d}' }}"), 195,
      "#{d} uses the '^' flag to uppercase the result.")
end
# hash (swap case)
[["%#b", "2020-06-15"], ["%#B", "2020-06-15"],
 ["%#a", "2020-06-15"], ["%#A", "2020-06-15"]].each do |d, input|
  add(specs, "date_flag_#{d.sub('%','pct_').gsub(/[^a-zA-Z0-9]/,'_')}_#{input.gsub(/[^0-9]/,'')}",
      "{{ '#{input}' | date: '#{d}' }}",
      r("{{ '#{input}' | date: '#{d}' }}"), 195,
      "#{d} uses the '#' flag to swap case. Ruby uppercases names that are normally mixed case.")
end

# ============================================================
# SECTION 7: composite format directives on a fixed datetime
# ============================================================
DT_FULL = "2020-06-15 14:30:45"
DT_FULL_TZ = "2020-06-15 14:30:45 -0400"
composites = [
  ["%D", DT_FULL, "06/15/20", 165, "%D == %m/%d/%y short date."],
  ["%F", DT_FULL, "2020-06-15", 165, "%F == %Y-%m-%d ISO 8601 date."],
  ["%R", DT_FULL, "14:30", 165, "%R == %H:%M 24-hour time."],
  ["%T", DT_FULL, "14:30:45", 165, "%T == %H:%M:%S 24-hour time with seconds."],
  ["%r", DT_FULL, "02:30:45 PM", 170, "%r == %I:%M:%S %p 12-hour time with AM/PM."],
  ["%c", DT_FULL, r("{{ '#{DT_FULL}' | date: '%c' }}"), 165, "%c locale's preferred date+time."],
  ["%x", DT_FULL, r("{{ '#{DT_FULL}' | date: '%x' }}"), 165, "%x locale's preferred date."],
  ["%X", DT_FULL, r("{{ '#{DT_FULL}' | date: '%X' }}"), 165, "%X locale's preferred time."],
]
composites.each do |d, input, _exp, c, hint|
  tmpl = "{{ '#{lit(input)}' | date: '#{d}' }}"
  add(specs, "date_composite_#{d.sub('%','pct_').gsub(/[^a-zA-Z0-9]/,'_')}",
      tmpl, r(tmpl), c, hint)
end

# RFC 822 / ISO 8601 full strings (combined)
add(specs, "date_combined_rfc822",
    "{{ '#{DT_FULL_TZ}' | date: '%a, %d %b %Y %H:%M:%S %z' }}",
    r("{{ '#{DT_FULL_TZ}' | date: '%a, %d %b %Y %H:%M:%S %z' }}"), 175,
    "RFC 822/2822 email/RSS date format: 'Mon, 15 Jun 2020 14:30:45 -0400'.")
add(specs, "date_combined_iso8601",
    "{{ '#{DT_FULL}' | date: '%Y-%m-%dT%H:%M:%S' }}",
    r("{{ '#{DT_FULL}' | date: '%Y-%m-%dT%H:%M:%S' }}"), 170,
    "ISO 8601 datetime: '2020-06-15T14:30:45'.")
add(specs, "date_combined_human",
    "{{ '#{DT_FULL}' | date: '%B %d, %Y at %I:%M %p' }}",
    r("{{ '#{DT_FULL}' | date: '%B %d, %Y at %I:%M %p' }}"), 170,
    "Human-readable date with literal text: 'June 15, 2020 at 02:30 PM'.")

# ============================================================
# SECTION 8: leap year + end-of-year day-of-year
# ============================================================
add(specs, "date_doy_leap_feb29",
    "{{ '2020-02-29' | date: '%j' }}",
    r("{{ '2020-02-29' | date: '%j' }}"), 185,
    "2020 is a leap year; Feb 29 is day 060.")
add(specs, "date_doy_leap_dec31",
    "{{ '2020-12-31' | date: '%j' }}",
    r("{{ '2020-12-31' | date: '%j' }}"), 185,
    "Dec 31 in a leap year is day 366.")
add(specs, "date_doy_nonleap_dec31",
    "{{ '2021-12-31' | date: '%j' }}",
    r("{{ '2021-12-31' | date: '%j' }}"), 185,
    "Dec 31 in a non-leap year is day 365.")
add(specs, "date_doy_jan1",
    "{{ '2020-01-01' | date: '%j' }}",
    r("{{ '2020-01-01' | date: '%j' }}"), 125,
    "Jan 1 is day 001.")

# ============================================================
# Output YAML
# ============================================================
require "yaml"

header = <<~HEADER
# Exhaustive date/time strftime spec for the Liquid `date` filter.
#
# The entire API surface of Ruby's Time#strftime is part of the Liquid spec:
# every format directive, every padding/case flag, every month, every weekday,
# and a range of timezone inputs. Expected values were captured from the
# reference Shopify/liquid (liquid-ruby) implementation.
#
# These specs do NOT depend on the ambient ENV["TZ"]. Timezone-sensitive
# directives (%z %Z %:z %::z %s) are always given an input that carries its
# own zone (an explicit "UTC" suffix or a numeric offset), so their output
# is identical under any timezone. Wall-clock directives are parsed as
# written and are likewise TZ-independent. 'now' is frozen to a Time.utc
# object (2024-01-01 00:01:58 UTC), whose %z/%Z are TZ-independent too.
#
# Reference documentation:
#   Ruby Time#strftime: https://ruby-doc.org/core/Time.html#method-i-strftime
#   Liquid `date` filter: https://shopify.dev/docs/api/liquid/filters#date
---
_metadata:
  hint: |
    The `date` filter formats a date using Ruby's Time#strftime directives.
    The entire Ruby strftime API surface is in scope: every %x directive
    (%a %A %b %B %c %C %d %D %e %F %G %g %H %h %I %j %k %l %L %M %m %N %n
    %p %P %R %r %S %s %t %T %U %u %V %W %w %X %x %Y %y %Z %z %%), the
    padding/case flags (- _ 0 ^ #), the colon timezone variants (%:z %::z),
    all 12 months, and all 7 weekdays.
    Input may be: Unix timestamp (int or numeric string), ISO 8601 / parseable
    date string, 'now', or 'today' (case-insensitive). 'now' is frozen to
    2024-01-01 00:01:58 UTC (a Time.utc object). These specs do NOT rely on
    the ambient ENV["TZ"]: every timezone-sensitive directive is given an
    input that carries its own zone (explicit "UTC" or a numeric offset),
    so expected values are stable under any timezone.
    Reference: https://ruby-doc.org/core/Time.html#method-i-strftime
  doc: filters/date.md
specs:
HEADER

puts header
specs.each do |s|
  puts "- name: #{s[:name]}"
  puts "  complexity: #{s[:complexity]}"
  puts "  hint: |"
  s[:hint].split("\n").each { |line| puts "    #{line}" }
  puts "  template: #{s[:template].inspect}"
  puts "  expected: #{s[:expected].inspect}"
end
