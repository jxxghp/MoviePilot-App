//! 插件表单条件表达式（v-show / v-if）安全沙箱求值器：禁止任何脚本执行，仅解释受控布尔与比较运算。

use serde_json::Value;

/// 插件表单安全条件表达式求值器。
pub struct NativeFormExpression;

impl NativeFormExpression {
    /// 基于当前表单模型评估 `v-show` / `v-if` 表达式的布尔真值。
    pub fn evaluate(expr: &str, model: &Value) -> bool {
        let mut trimmed = expr.trim();
        if let Some(inner) = trimmed
            .strip_prefix("{{")
            .and_then(|rest| rest.strip_suffix("}}"))
        {
            trimmed = inner.trim();
        }
        if trimmed.is_empty() {
            return true;
        }
        Self::eval_or(trimmed, model)
    }

    fn eval_or(expr: &str, model: &Value) -> bool {
        if let Some(parts) = Self::split_top_level(expr, "||") {
            return parts.into_iter().any(|p| Self::eval_and(p, model));
        }
        Self::eval_and(expr, model)
    }

    fn eval_and(expr: &str, model: &Value) -> bool {
        if let Some(parts) = Self::split_top_level(expr, "&&") {
            return parts.into_iter().all(|p| Self::eval_unary(p, model));
        }
        Self::eval_unary(expr, model)
    }

    fn eval_unary(expr: &str, model: &Value) -> bool {
        let s = Self::strip_outer_parens(expr.trim());
        if let Some(inner) = s.strip_prefix('!') {
            return !Self::eval_unary(inner, model);
        }
        for (op, strict, negate) in [
            ("===", true, false),
            ("!==", true, true),
            ("==", false, false),
            ("!=", false, true),
        ] {
            if let Some((lhs, rhs)) = Self::split_once_top_level(s, op) {
                let lv = Self::resolve_value(lhs.trim(), model);
                let rv = Self::resolve_value(rhs.trim(), model);
                let eq = if strict {
                    Self::values_strict_equal(&lv, &rv)
                } else {
                    Self::values_equal(&lv, &rv)
                };
                return if negate { !eq } else { eq };
            }
        }
        for op in ["<=", ">=", "<", ">"] {
            if let Some((lhs, rhs)) = Self::split_once_top_level(s, op) {
                let lv = Self::resolve_value(lhs.trim(), model);
                let rv = Self::resolve_value(rhs.trim(), model);
                if let (Some(a), Some(b)) = (Self::as_f64(&lv), Self::as_f64(&rv)) {
                    return match op {
                        "<=" => a <= b,
                        ">=" => a >= b,
                        "<" => a < b,
                        ">" => a > b,
                        _ => false,
                    };
                }
                return false;
            }
        }
        let val = Self::resolve_value(s, model);
        Self::is_truthy(&val)
    }

    fn resolve_value(token: &str, model: &Value) -> Value {
        let s = Self::strip_outer_parens(token.trim());
        match s {
            "true" => return Value::Bool(true),
            "false" => return Value::Bool(false),
            "null" | "undefined" => return Value::Null,
            _ => {}
        }
        if ((s.starts_with('\'') && s.ends_with('\'')) || (s.starts_with('"') && s.ends_with('"')))
            && s.len() >= 2
        {
            return Value::String(s[1..s.len() - 1].to_string());
        }
        if let Ok(n) = s.parse::<i64>() {
            return Value::Number(n.into());
        }
        if let Ok(f) = s.parse::<f64>()
            && let Some(num) = serde_json::Number::from_f64(f)
        {
            return Value::Number(num);
        }
        // 支持 model.foo.bar 或直接 foo.bar 属性路径
        let path = s.strip_prefix("model.").unwrap_or(s);
        let mut cursor = model;
        for seg in path.split('.') {
            if let Some(next) = cursor.get(seg) {
                cursor = next;
            } else {
                return Value::Null;
            }
        }
        cursor.clone()
    }

    fn as_f64(v: &Value) -> Option<f64> {
        match v {
            Value::Number(n) => n.as_f64(),
            Value::String(s) => s.trim().parse::<f64>().ok(),
            _ => None,
        }
    }

    fn values_strict_equal(a: &Value, b: &Value) -> bool {
        match (a, b) {
            (Value::Number(na), Value::Number(nb)) => na.as_f64() == nb.as_f64(),
            _ => a == b,
        }
    }

    fn values_equal(a: &Value, b: &Value) -> bool {
        if Self::values_strict_equal(a, b) {
            return true;
        }
        match (a, b) {
            (Value::Number(na), Value::String(sb)) => sb.trim().parse::<f64>().ok() == na.as_f64(),
            (Value::String(sa), Value::Number(nb)) => sa.trim().parse::<f64>().ok() == nb.as_f64(),
            _ => false,
        }
    }

    fn is_truthy(v: &Value) -> bool {
        match v {
            Value::Null => false,
            Value::Bool(b) => *b,
            Value::Number(n) => n.as_f64().is_some_and(|x| x != 0.0 && !x.is_nan()),
            Value::String(s) => !s.is_empty(),
            Value::Array(_) | Value::Object(_) => true,
        }
    }

    fn strip_outer_parens(mut s: &str) -> &str {
        while s.starts_with('(') && s.ends_with(')') {
            let inner = &s[1..s.len() - 1];
            let mut depth = 0i32;
            let mut balanced = true;
            for ch in inner.chars() {
                match ch {
                    '(' => depth += 1,
                    ')' => {
                        depth -= 1;
                        if depth < 0 {
                            balanced = false;
                            break;
                        }
                    }
                    _ => {}
                }
            }
            if balanced && depth == 0 {
                s = inner.trim();
            } else {
                break;
            }
        }
        s
    }

    fn split_top_level<'a>(s: &'a str, sep: &str) -> Option<Vec<&'a str>> {
        let mut out = Vec::new();
        let bytes = s.as_bytes();
        let sep_bytes = sep.as_bytes();
        let mut depth = 0i32;
        let mut in_quote: Option<u8> = None;
        let mut start = 0;
        let mut i = 0;
        while i < bytes.len() {
            let b = bytes[i];
            if let Some(q) = in_quote {
                if b == q {
                    in_quote = None;
                }
                i += 1;
                continue;
            }
            match b {
                b'\'' | b'"' => in_quote = Some(b),
                b'(' => depth += 1,
                b')' => depth -= 1,
                _ => {}
            }
            if depth == 0 && bytes[i..].starts_with(sep_bytes) {
                out.push(&s[start..i]);
                i += sep_bytes.len();
                start = i;
                continue;
            }
            i += 1;
        }
        if out.is_empty() {
            None
        } else {
            out.push(&s[start..]);
            Some(out)
        }
    }

    fn split_once_top_level<'a>(s: &'a str, sep: &str) -> Option<(&'a str, &'a str)> {
        let parts = Self::split_top_level(s, sep)?;
        if parts.len() >= 2 {
            let first = parts[0];
            let rest = &s[first.len() + sep.len()..];
            Some((first, rest))
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn evaluates_boolean_and_equality_expressions() {
        let model = serde_json::json!({"enabled": true, "mode": "cron", "retries": 3});
        assert!(NativeFormExpression::evaluate("enabled", &model));
        assert!(!NativeFormExpression::evaluate("!enabled", &model));
        assert!(NativeFormExpression::evaluate(
            "enabled && mode == 'cron'",
            &model
        ));
        assert!(NativeFormExpression::evaluate(
            "mode == 'manual' || retries == 3",
            &model
        ));
        assert!(!NativeFormExpression::evaluate("false", &model));
    }
}
