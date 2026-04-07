package com.claudemulti.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.sp
import com.claudemulti.protocol.SessionBounds
import com.claudemulti.protocol.TerminalSession

/**
 * A Compose Canvas that draws a scaled map of all terminal sessions.
 *
 * Each session is rendered as a rounded rectangle proportional to its bounds.
 * The selected session is highlighted with an accent fill and thicker border.
 * If no sessions are present, "No sessions" text is drawn in the center.
 */
@Composable
fun WindowMapView(
    sessions: List<TerminalSession>,
    screenBounds: SessionBounds,
    selectedSessionId: String?,
    modifier: Modifier = Modifier
) {
    val textMeasurer = rememberTextMeasurer()

    val accentColor = MaterialTheme.colorScheme.primary
    val normalBorderColor = MaterialTheme.colorScheme.outline
    val selectedFillColor = accentColor.copy(alpha = 0.3f)
    val normalFillColor = Color(0xFF2196F3).copy(alpha = 0.15f) // Blue at 15% opacity
    val labelColor = MaterialTheme.colorScheme.onSurface
    val labelStyle = TextStyle(fontSize = 10.sp, color = labelColor)
    val emptyStyle = TextStyle(
        fontSize = 14.sp,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )

    Canvas(modifier = modifier.fillMaxSize()) {
        if (sessions.isEmpty()) {
            // Draw "No sessions" centered
            val noSessionsText = "No sessions"
            val measured = textMeasurer.measure(noSessionsText, emptyStyle)
            drawText(
                textMeasurer = textMeasurer,
                text = noSessionsText,
                style = emptyStyle,
                topLeft = Offset(
                    x = (size.width - measured.size.width) / 2f,
                    y = (size.height - measured.size.height) / 2f
                )
            )
            return@Canvas
        }

        // Use screenBounds to determine the coordinate space
        val totalWidth = screenBounds.width.coerceAtLeast(1.0)
        val totalHeight = screenBounds.height.coerceAtLeast(1.0)
        val originX = screenBounds.x
        val originY = screenBounds.y

        // Calculate scale to fit screenBounds into the Canvas size (preserving aspect ratio)
        val padding = 16f
        val availableWidth = size.width - padding * 2
        val availableHeight = size.height - padding * 2
        val scale = minOf(
            availableWidth / totalWidth.toFloat(),
            availableHeight / totalHeight.toFloat()
        )

        // Center the drawing within the canvas
        val scaledTotalWidth = totalWidth.toFloat() * scale
        val scaledTotalHeight = totalHeight.toFloat() * scale
        val offsetX = padding + (availableWidth - scaledTotalWidth) / 2f
        val offsetY = padding + (availableHeight - scaledTotalHeight) / 2f

        val cornerRadius = CornerRadius(6f, 6f)

        // Draw each session
        for (session in sessions) {
            val b = session.bounds
            val isSelected = session.id == selectedSessionId

            val x = offsetX + ((b.x - originX) * scale).toFloat()
            val y = offsetY + ((b.y - originY) * scale).toFloat()
            val w = (b.width * scale).toFloat()
            val h = (b.height * scale).toFloat()

            // Fill
            drawRoundRect(
                color = if (isSelected) selectedFillColor else normalFillColor,
                topLeft = Offset(x, y),
                size = Size(w, h),
                cornerRadius = cornerRadius
            )

            // Border
            drawRoundRect(
                color = if (isSelected) accentColor else normalBorderColor,
                topLeft = Offset(x, y),
                size = Size(w, h),
                cornerRadius = cornerRadius,
                style = Stroke(width = if (isSelected) 3f else 1f)
            )

            // Label: draw session title (truncated) centered in the rectangle
            if (w > 40f && h > 20f) {
                val label = session.title.take(24)
                val maxTextWidth = (w - 12f).toInt().coerceAtLeast(1)
                val maxTextHeight = (h - 8f).toInt().coerceAtLeast(1)

                val textResult = textMeasurer.measure(
                    text = label,
                    style = labelStyle,
                    overflow = TextOverflow.Ellipsis,
                    maxLines = 1,
                    constraints = Constraints(
                        maxWidth = maxTextWidth,
                        maxHeight = maxTextHeight
                    )
                )

                // Center the text within the rectangle
                val textX = x + (w - textResult.size.width) / 2f
                val textY = y + (h - textResult.size.height) / 2f

                drawText(
                    textLayoutResult = textResult,
                    topLeft = Offset(textX, textY)
                )
            }
        }
    }
}
