/* Small Intl.DateTimeFormat subset backed by V host time fields. */

const { intl_date_time_parts } = globalThis.__bootstrap;

const enMonthsShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const enMonthsLong = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];
const enWeekdaysShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const enWeekdaysLong = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const zhWeekdaysShort = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
const zhWeekdaysLong = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"];

function canonicalLocale(locale) {
  if (Array.isArray(locale)) {
    return canonicalLocale(locale[0]);
  }
  return String(locale || "en-US");
}

function normalizeOptions(options = {}) {
  const normalized = { ...options };
  const hasDateTimeStyle = normalized.dateStyle !== undefined || normalized.timeStyle !== undefined;
  const hasComponent =
    normalized.weekday !== undefined ||
    normalized.year !== undefined ||
    normalized.month !== undefined ||
    normalized.day !== undefined ||
    normalized.hour !== undefined ||
    normalized.minute !== undefined ||
    normalized.second !== undefined;
  if (!hasDateTimeStyle && !hasComponent) {
    normalized.year = "numeric";
    normalized.month = "numeric";
    normalized.day = "numeric";
  }
  if (normalized.dateStyle !== undefined) {
    normalized.year = "numeric";
    normalized.month = normalized.dateStyle === "full" || normalized.dateStyle === "long" ? "long" : "numeric";
    normalized.day = "numeric";
    if (normalized.dateStyle === "full") normalized.weekday = "long";
  }
  if (normalized.timeStyle !== undefined) {
    normalized.hour = "numeric";
    normalized.minute = "2-digit";
    if (normalized.timeStyle !== "short") normalized.second = "2-digit";
  }
  return normalized;
}

function pad2(value) {
  return String(value).padStart(2, "0");
}

function monthValue(month, style, locale) {
  if (style === "2-digit") return pad2(month);
  if (style === "short") return locale.startsWith("zh") ? `${month}月` : enMonthsShort[month - 1];
  if (style === "long") return locale.startsWith("zh") ? `${month}月` : enMonthsLong[month - 1];
  return String(month);
}

function weekdayValue(weekday, style, locale) {
  if (locale.startsWith("zh")) {
    return style === "long" ? zhWeekdaysLong[weekday] : zhWeekdaysShort[weekday];
  }
  return style === "long" ? enWeekdaysLong[weekday] : enWeekdaysShort[weekday];
}

function numericPart(type, value, style) {
  return { type, value: style === "2-digit" ? pad2(value) : String(value) };
}

function dateParts(fields, options, locale) {
  const year = options.year ? [{ type: "year", value: String(fields.year) }] : [];
  const month = options.month ? [{ type: "month", value: monthValue(fields.month, options.month, locale) }] : [];
  const day = options.day ? [numericPart("day", fields.day, options.day)] : [];
  const weekday = options.weekday ? [{ type: "weekday", value: weekdayValue(fields.weekday, options.weekday, locale) }] : [];
  if (locale.startsWith("zh")) {
    const parts = [];
    parts.push(...year);
    if (year.length && month.length) parts.push({ type: "literal", value: "/" });
    parts.push(...month);
    if ((year.length || month.length) && day.length) parts.push({ type: "literal", value: "/" });
    parts.push(...day);
    if (weekday.length && parts.length) parts.push({ type: "literal", value: " " });
    parts.push(...weekday);
    return parts;
  }
  const parts = [];
  parts.push(...month);
  if (month.length && day.length) parts.push({ type: "literal", value: "/" });
  parts.push(...day);
  if ((month.length || day.length) && year.length) parts.push({ type: "literal", value: "/" });
  parts.push(...year);
  if (weekday.length && parts.length) parts.push({ type: "literal", value: ", " });
  parts.push(...weekday);
  return parts;
}

function timeParts(fields, options) {
  if (!options.hour && !options.minute && !options.second) return [];
  const hour12 = options.hour12 === true;
  let hour = fields.hour;
  const dayPeriod = hour < 12 ? "AM" : "PM";
  if (hour12) {
    hour %= 12;
    if (hour === 0) hour = 12;
  }
  const parts = [];
  if (options.hour) parts.push(numericPart("hour", hour, options.hour));
  if (options.minute) {
    if (parts.length) parts.push({ type: "literal", value: ":" });
    parts.push(numericPart("minute", fields.minute, options.minute));
  }
  if (options.second) {
    if (parts.length) parts.push({ type: "literal", value: ":" });
    parts.push(numericPart("second", fields.second, options.second));
  }
  if (hour12) {
    parts.push({ type: "literal", value: " " });
    parts.push({ type: "dayPeriod", value: dayPeriod });
  }
  return parts;
}

function dateFromInput(value) {
  if (value === undefined) return new Date();
  const date = value instanceof Date ? value : new Date(value);
  const ms = date.getTime();
  if (!Number.isFinite(ms)) throw new RangeError("Invalid time value");
  return date;
}

class DateTimeFormat {
  constructor(locales = "en-US", options = {}) {
    this.locale = canonicalLocale(locales);
    this.options = normalizeOptions(options);
  }

  format(value) {
    return this.formatToParts(value).map((part) => part.value).join("");
  }

  formatToParts(value) {
    const inputDate = dateFromInput(value);
    const timeZone = this.options.timeZone === "UTC" ? "UTC" : "local";
    const fields = intl_date_time_parts(Math.trunc(inputDate.getTime()), timeZone);
    const date = dateParts(fields, this.options, this.locale);
    const time = timeParts(fields, this.options);
    if (date.length > 0 && time.length > 0) {
      return [...date, { type: "literal", value: ", " }, ...time];
    }
    return [...date, ...time];
  }

  resolvedOptions() {
    return {
      locale: this.locale,
      calendar: "gregory",
      numberingSystem: "latn",
      timeZone: this.options.timeZone === "UTC" ? "UTC" : "local",
      ...this.options,
    };
  }
}

function supportedLocalesOf(locales) {
  return Array.isArray(locales) ? locales.map(canonicalLocale) : [canonicalLocale(locales)];
}

DateTimeFormat.supportedLocalesOf = supportedLocalesOf;

globalThis.Intl = {
  ...(globalThis.Intl || {}),
  DateTimeFormat,
};
