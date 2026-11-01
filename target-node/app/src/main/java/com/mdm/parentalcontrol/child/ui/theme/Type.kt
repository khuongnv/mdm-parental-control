package com.mdm.parentalcontrol.child.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.mdm.parentalcontrol.child.R

// Apple SF Pro Display typography directly referencing bundled font asset
val SFProDisplay = FontFamily(
    Font(R.font.sf_pro_display_regular, FontWeight.Normal),
    Font(R.font.sf_pro_display_regular, FontWeight.Medium),
    Font(R.font.sf_pro_display_regular, FontWeight.SemiBold),
    Font(R.font.sf_pro_display_regular, FontWeight.Bold)
)

val ChildTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = SFProDisplay,
        fontWeight = FontWeight.Bold,
        fontSize = 34.sp,
        lineHeight = 41.sp,
        letterSpacing = 0.37.sp
    ),
    headlineLarge = TextStyle(
        fontFamily = SFProDisplay,
        fontWeight = FontWeight.SemiBold,
        fontSize = 22.sp,
        lineHeight = 28.sp,
        letterSpacing = 0.35.sp
    ),
    titleLarge = TextStyle(
        fontFamily = SFProDisplay,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
        lineHeight = 25.sp,
        letterSpacing = 0.38.sp
    ),
    bodyLarge = TextStyle(
        fontFamily = SFProDisplay,
        fontWeight = FontWeight.Normal,
        fontSize = 17.sp,
        lineHeight = 22.sp,
        letterSpacing = (-0.41).sp
    ),
    bodyMedium = TextStyle(
        fontFamily = SFProDisplay,
        fontWeight = FontWeight.Normal,
        fontSize = 15.sp,
        lineHeight = 20.sp,
        letterSpacing = (-0.24).sp
    ),
    labelSmall = TextStyle(
        fontFamily = SFProDisplay,
        fontWeight = FontWeight.Medium,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.sp
    )
)
