package com.paply.android.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.paply.android.ui.theme.PaplyColors as C

@Composable
fun Glyph(icon: ImageVector, description: String? = null, tint: Color = C.text, size: Dp = 20.dp) {
    val scale = LocalDensity.current.fontScale.coerceAtMost(2.4f)
    Icon(icon, contentDescription = description, tint = tint, modifier = Modifier.size(size * scale))
}

@Composable
fun PaplyCard(modifier: Modifier = Modifier, radius: Dp = 20.dp, color: Color = C.row,
    borderColor: Color = Color.White.copy(alpha = 0.12f), shadow: Dp = 0.dp,
    contentPadding: PaddingValues = PaddingValues(16.dp), content: @Composable ColumnScope.() -> Unit) {
    Surface(modifier, shape = RoundedCornerShape(radius), color = color, shadowElevation = shadow,
        border = BorderStroke(0.5.dp, borderColor)) {
        Column(Modifier.fillMaxWidth().padding(contentPadding), content = content)
    }
}

@Composable
fun Section(title: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        if (title != null) Text(title, style = MaterialTheme.typography.bodySmall, color = C.secondary,
            modifier = Modifier.padding(start = 16.dp).semantics { heading() })
        Surface(shape = RoundedCornerShape(16.dp), color = C.row) {
            Column(Modifier.fillMaxWidth(), content = content)
        }
        if (footer != null) Text(footer, style = MaterialTheme.typography.bodySmall, color = C.secondary,
            modifier = Modifier.padding(horizontal = 16.dp))
    }
}

@Composable
fun SettingsItem(title: String, modifier: Modifier = Modifier, icon: ImageVector? = null,
    value: String? = null, onClick: (() -> Unit)? = null, trailing: (@Composable () -> Unit)? = null,
) {
    Row(modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
        .heightIn(min = 54.dp).padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (icon != null) Box(Modifier.size(29.dp).background(Color.White.copy(alpha = 0.1f), RoundedCornerShape(7.dp)),
            contentAlignment = Alignment.Center) { Icon(icon, null, tint = C.text, modifier = Modifier.size(17.dp)) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (value != null) Text(value, style = MaterialTheme.typography.bodySmall, color = C.secondary)
        }
        if (trailing != null) trailing()
        else if (onClick != null) Glyph(PaplyIcons.Chevron, tint = C.tertiary, size = 16.dp)
    }
}

@Composable
fun Hairline() { HorizontalDivider(Modifier.padding(start = 16.dp), thickness = 0.5.dp, color = Color.White.copy(alpha = 0.08f)) }

@Composable
fun Pill(title: String, onClick: () -> Unit, prominent: Boolean = true, enabled: Boolean = true) {
    Button(onClick = onClick, enabled = enabled, shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = if (prominent) C.greenBright else Color.White.copy(alpha = 0.1f),
            contentColor = if (prominent) C.forest else C.text),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp)) {
        Text(title, style = MaterialTheme.typography.labelLarge)
    }
}

@Composable
fun BetaBadge() {
    Surface(color = C.thoughtMint.copy(alpha = 0.12f), shape = CircleShape,
        border = BorderStroke(0.5.dp, C.thoughtMint.copy(alpha = 0.22f))) {
        Text("Beta", color = C.thoughtMint.copy(alpha = 0.9f), style = MaterialTheme.typography.labelMedium,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp).semantics { contentDescription = "Beta-Funktion" })
    }
}

@Composable
fun PageHeader(title: String, back: (() -> Unit)? = null, settings: (() -> Unit)? = null,
    beta: Boolean = false, done: (() -> Unit)? = null, large: Boolean = true,
) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
            if (back != null) IconButton(onClick = back) { Glyph(PaplyIcons.Back, "Zurück", C.greenBright) }
            else if (beta) BetaBadge()
            Spacer(Modifier.weight(1f))
            if (settings != null) IconButton(onClick = settings) { Glyph(PaplyIcons.Settings, "Einstellungen", C.greenBright, 22.dp) }
            if (done != null) TextButton(onClick = done) { Text("Fertig", fontWeight = FontWeight.SemiBold) }
        }
        Text(title, style = if (large) MaterialTheme.typography.headlineLarge else MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 2.dp, bottom = 16.dp).semantics { heading() })
    }
}

@Composable
fun StatusLine(title: String, done: Boolean) {
    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp).semantics(mergeDescendants = true) {
        stateDescription = if (done) "erledigt" else "offen"
    }, horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Glyph(if (done) PaplyIcons.Check else PaplyIcons.Circle, tint = if (done) C.greenBright else C.tertiary)
        Text(title, style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
fun EmptyState(title: String, description: String, icon: ImageVector) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 28.dp, vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(72.dp).background(C.thoughtMint.copy(alpha = 0.09f), CircleShape), contentAlignment = Alignment.Center) {
            Glyph(icon, tint = C.thoughtMint, size = 32.dp)
        }
        Text(title, style = MaterialTheme.typography.titleLarge, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            modifier = Modifier.semantics { heading() })
        Text(description, style = MaterialTheme.typography.bodyMedium, color = C.secondary,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}

/** One TalkBack switch target for the whole row, including the label; no nested click targets. */
@Composable
fun SettingsToggle(title: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit,
    icon: ImageVector? = null, description: String = title,
) {
    SettingsItem(title, icon = icon, modifier = Modifier.toggleable(checked, role = Role.Switch, onValueChange = onCheckedChange)
        .semantics(mergeDescendants = true) { contentDescription = description }, trailing = {
        Switch(checked, onCheckedChange = null, colors = SwitchDefaults.colors(
            checkedThumbColor = C.text, checkedTrackColor = C.greenBright,
            uncheckedThumbColor = C.text.copy(alpha = 0.65f), uncheckedTrackColor = Color.White.copy(alpha = 0.12f),
            uncheckedBorderColor = Color.White.copy(alpha = 0.18f)))
    })
}
