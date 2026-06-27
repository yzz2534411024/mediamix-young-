package com.mediamix.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Format milliseconds to MM:SS or HH:MM:SS
 */
fun formatDuration(durationMs: Long): String {
    if (durationMs <= 0) return "00:00"
    val totalSeconds = durationMs / 1000
    val hours = totalSeconds / 3600
    val minutes = (totalSeconds % 3600) / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) {
        String.format("%02d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format("%02d:%02d", minutes, seconds)
    }
}

// ============================================================================
// Subtitle Overlay
// ============================================================================

@Composable
fun SubtitleOverlay(
    subtitleText: String?,
    modifier: Modifier = Modifier
) {
    if (subtitleText.isNullOrBlank()) return
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp, vertical = 60.dp),
        contentAlignment = Alignment.BottomCenter
    ) {
        Text(
            text = subtitleText,
            color = Color.White,
            fontSize = 18.sp,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .background(
                    Color.Black.copy(alpha = 0.6f),
                    RoundedCornerShape(4.dp)
                )
                .padding(horizontal = 12.dp, vertical = 4.dp)
        )
    }
}

// ============================================================================
// Seeking Overlay
// ============================================================================

@Composable
fun SeekingOverlay(
    seekPositionText: String,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Row(
            modifier = Modifier
                .background(Color.Black.copy(alpha = 0.87f), RoundedCornerShape(12.dp))
                .padding(horizontal = 24.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                color = Color.White,
                strokeWidth = 2.dp
            )
            Text(
                text = seekPositionText,
                color = Color.White,
                fontSize = 14.sp
            )
        }
    }
}

// ============================================================================
// Speed Indicator
// ============================================================================

@Composable
fun SpeedIndicator(
    speed: Float,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .padding(top = 60.dp, end = 16.dp)
            .background(Color.Black.copy(alpha = 0.87f), RoundedCornerShape(8.dp))
            .padding(horizontal = 12.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = "${speed}x",
            color = Color.White,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

// ============================================================================
// Lock Icon (shown when screen is locked)
// ============================================================================

@Composable
fun LockIcon(
    onUnlock: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(32.dp))
                .background(Color.Black.copy(alpha = 0.45f))
                .clickable(onClick = onUnlock)
                .padding(16.dp),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.Lock,
                contentDescription = "Unlock",
                tint = Color.White,
                modifier = Modifier.size(32.dp)
            )
        }
    }
}

// ============================================================================
// Brightness Indicator
// ============================================================================

@Composable
fun BrightnessIndicator(
    brightness: Float,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .background(Color.Black.copy(alpha = 0.87f), RoundedCornerShape(12.dp))
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = Icons.Default.BrightnessMedium,
                contentDescription = "Brightness",
                tint = Color.White,
                modifier = Modifier.size(32.dp)
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Brightness ${(brightness * 100).toInt()}%",
                color = Color.White,
                fontSize = 14.sp
            )
        }
    }
}

// ============================================================================
// Volume Indicator
// ============================================================================

@Composable
fun VolumeIndicator(
    volume: Float,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .background(Color.Black.copy(alpha = 0.87f), RoundedCornerShape(12.dp))
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = if (volume == 0f) Icons.Default.VolumeOff else Icons.Default.VolumeUp,
                contentDescription = "Volume",
                tint = Color.White,
                modifier = Modifier.size(32.dp)
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Volume ${(volume * 100).toInt()}%",
                color = Color.White,
                fontSize = 14.sp
            )
        }
    }
}

// ============================================================================
// Loading Overlay
// ============================================================================

@Composable
fun LoadingOverlay(
    loadingText: String,
    bufferedPercentage: Int,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .background(Color.Black.copy(alpha = 0.87f), RoundedCornerShape(16.dp))
                .padding(horizontal = 32.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(40.dp),
                color = Color.White,
                strokeWidth = 3.dp
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = loadingText,
                color = Color.White,
                fontSize = 16.sp
            )
            if (bufferedPercentage > 0) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Buffer: $bufferedPercentage%",
                    color = Color.White.copy(alpha = 0.7f),
                    fontSize = 13.sp
                )
            }
        }
    }
}

// ============================================================================
// Error Overlay
// ============================================================================

@Composable
fun ErrorOverlay(
    errorMessage: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .background(Color.Black.copy(alpha = 0.87f), RoundedCornerShape(16.dp))
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = Icons.Default.ErrorOutline,
                contentDescription = "Error",
                tint = Color.Red,
                modifier = Modifier.size(48.dp)
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = if (errorMessage.length > 100) errorMessage.take(100) + "..." else errorMessage,
                color = Color.White,
                fontSize = 14.sp,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(16.dp))
            Button(
                onClick = onRetry,
                colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = 0.2f))
            ) {
                Text("Retry", color = Color.White)
            }
        }
    }
}
