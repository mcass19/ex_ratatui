use rustler::{Decoder, Error, Term};
use std::collections::HashMap;

pub type TermMap<'a> = HashMap<String, Term<'a>>;

pub fn decode_map<'a>(term: Term<'a>, context: &str) -> Result<TermMap<'a>, Error> {
    term.decode()
        .map_err(|_| error_message(format!("{context}: expected a map")))
}

pub fn decode_required<'a, T>(
    map: &TermMap<'a>,
    field: &'static str,
    context: &str,
) -> Result<T, Error>
where
    T: Decoder<'a>,
{
    match map.get(field).copied() {
        Some(term) => term
            .decode()
            .map_err(|_| invalid_field(context, field, "unexpected value")),
        None => Err(missing_field(context, field)),
    }
}

pub fn decode_optional<'a, T>(
    map: &TermMap<'a>,
    field: &'static str,
    context: &str,
) -> Result<Option<T>, Error>
where
    T: Decoder<'a>,
{
    match map.get(field).copied() {
        Some(term) => term
            .decode()
            .map(Some)
            .map_err(|_| invalid_field(context, field, "unexpected value")),
        None => Ok(None),
    }
}

pub fn optional_term<'a>(map: &TermMap<'a>, field: &'static str) -> Option<Term<'a>> {
    map.get(field).copied()
}

pub fn missing_field(context: &str, field: &str) -> Error {
    error_message(format!("{context}.{field}: missing required field"))
}

pub fn invalid_field(context: &str, field: &str, reason: &str) -> Error {
    error_message(format!("{context}.{field}: {reason}"))
}

pub fn error_message(message: String) -> Error {
    Error::Term(Box::new(message))
}
