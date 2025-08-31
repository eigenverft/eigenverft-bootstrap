using System;

using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Eigenverft.Bootstrapper
{
    public class ProgressBarEx3 : ProgressBar
    {
        #region Win32 theming interop

        [DllImport("uxtheme.dll")]
        private static extern int SetWindowTheme(IntPtr hWnd, string appname, string idlist);

        #endregion Win32 theming interop

        /// <summary>Controls whether text is drawn.</summary>
        public enum DisplayTextTypeEnum
        {
            /// <summary>Draw nothing.</summary>
            Blank,

            /// <summary>Draw <see cref="CustomText"/> centered in the control.</summary>
            CustomText
        }

        /// <summary>Border style for the control.</summary>
        public enum BorderStyleEnum
        {
            /// <summary>No border.</summary>
            None,

            /// <summary>One-pixel solid border using system control dark color.</summary>
            Solid
        }

        /// <summary>Text angle.</summary>
        public enum TextAngleEnum
        {
            /// <summary>Normal, baseline left-to-right.</summary>
            Normal,

            /// <summary>Vertical rotated clockwise.</summary>
            Vertical
        }

        /// <summary>Fill orientation.</summary>
        public enum OrientationEnum
        {
            /// <summary>Left-to-right fill.</summary>
            Horizontal,

            /// <summary>Bottom-to-top fill.</summary>
            Vertical
        }

        private string _customText;

        /// <summary>Gets or sets the custom text to render when <see cref="DisplayTextType"/> is <see cref="DisplayTextTypeEnum.CustomText"/>.</summary>
        /// <remarks>Setting this property triggers a repaint.</remarks>
        /// <example>
        /// <code>
        /// progressBarEx1.CustomText = "Working…";
        /// progressBarEx1.DisplayTextType = ProgressBarEx.DisplayTextTypeEnum.CustomText;
        /// </code>
        /// </example>
        [Description("The custom text to draw when DisplayTextType is CustomText."), Category("Appearance")]
        public string CustomText
        {
            get { return _customText; }
            set { _customText = value; Invalidate(); }
        }

        /// <summary>Gets or sets the font for the custom text.</summary>
        [Description("Font used to render the custom text."), Category("Appearance")]
        public Font CustomTextFont { get; set; }

        /// <summary>Gets or sets the color for the custom text.</summary>
        [DefaultValue(typeof(Color), "Black")]
        [Description("Color used to render the custom text."), Category("Appearance")]
        public Color CustomTextColor { get; set; }

        /// <summary>Gets or sets the background color of the unfilled area.</summary>
        [DefaultValue(typeof(Color), "Control")]
        [Description("Background color for the unfilled area of the bar."), Category("Appearance")]
        public Color BarBackgroundColor { get; set; }

        /// <summary>Gets or sets the starting color of the gradient fill.</summary>
        [DefaultValue(typeof(Color), "174, 245, 182")]
        [Description("Gradient start color for the filled portion."), Category("Appearance")]
        public Color GradientStartColor { get; set; }

        /// <summary>Gets or sets the ending color of the gradient fill.</summary>
        [DefaultValue(typeof(Color), "7, 204, 44")]
        [Description("Gradient end color for the filled portion."), Category("Appearance")]
        public Color GradientEndColor { get; set; }

        /// <summary>Gets or sets whether and how text is displayed.</summary>
        [DefaultValue(DisplayTextTypeEnum.CustomText)]
        [Description("Choose whether to draw custom text or leave blank."), Category("Behavior")]
        public DisplayTextTypeEnum DisplayTextType { get; set; }

        /// <summary>Gets or sets the border style.</summary>
        [DefaultValue(BorderStyleEnum.Solid)]
        [Description("Draw a 1px solid border or none."), Category("Appearance")]
        public BorderStyleEnum BorderStyle { get; set; }

        /// <summary>Gets or sets the orientation for fill and gradient.</summary>
        [DefaultValue(OrientationEnum.Horizontal)]
        [Description("Horizontal (left-to-right) or vertical (bottom-to-top) fill."), Category("Behavior")]
        public OrientationEnum Orientation { get; set; }

        /// <summary>Gets or sets the text angle.</summary>
        [DefaultValue(TextAngleEnum.Normal)]
        [Description("Text orientation: normal or vertical."), Category("Appearance")]
        public TextAngleEnum TextAngle { get; set; }

        /// <summary>
        /// Gets or sets the background transparency in percent (0..100).
        /// </summary>
        /// <remarks>
        /// 0 means fully opaque; 100 means fully transparent. The hue comes from <see cref="BarBackgroundColor"/>.
        /// </remarks>
        /// <example>
        /// <code>
        /// // 40% transparent background
        /// progressBarEx1.BackgroundTransparencyPercent = 40;
        /// </code>
        /// </example>
        [DefaultValue(0)]
        [Description("Background transparency in percent (0..100). 0 = opaque, 100 = fully transparent."), Category("Appearance")]
        public int BackgroundTransparencyPercent
        {
            get { return _backgroundTransparencyPercent; }
            set { _backgroundTransparencyPercent = Clamp(value, 0, 100); Invalidate(); }
        }

        private int _backgroundTransparencyPercent;

        /// <summary>Initializes a new instance with gradient + custom text and reduced flicker.</summary>
        public ProgressBarEx3()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            // Optional: support transparent back color scenarios.
            SetStyle(ControlStyles.SupportsTransparentBackColor, true);

            CustomTextFont = new Font("Microsoft Sans Serif", 8.5f, FontStyle.Regular);
            CustomTextColor = Color.Black;
            BarBackgroundColor = SystemColors.Control;
            GradientStartColor = Color.FromArgb(174, 245, 182);
            GradientEndColor = Color.FromArgb(7, 204, 44);

            DisplayTextType = DisplayTextTypeEnum.CustomText;
            Orientation = OrientationEnum.Horizontal;
            BorderStyle = BorderStyleEnum.Solid;
            TextAngle = TextAngleEnum.Normal;
            BackgroundTransparencyPercent = 0; // Opaque by default
        }

        /// <inheritdoc />
        protected override void OnHandleCreated(EventArgs e)
        {
            try { SetWindowTheme(this.Handle, null, null); } catch { /* best effort */ }
            base.OnHandleCreated(e);
        }

        /// <summary>Add WS_EX_COMPOSITED to further reduce flicker.</summary>
        protected override CreateParams CreateParams
        {
            get
            {
                const int WS_EX_COMPOSITED = 0x02000000;
                var cp = base.CreateParams;
                cp.ExStyle |= WS_EX_COMPOSITED;
                return cp;
            }
        }

        /// <summary>
        /// Paint the parent's background so semi-transparent overlays blend nicely,
        /// then draw our semi-transparent background and gradient fill.
        /// </summary>
        protected override void OnPaintBackground(PaintEventArgs e)
        {
            if (Parent != null)
            {
                var state = e.Graphics.Save();
                try
                {
                    // Ask the parent to paint into our background (simulate true transparency)
                    e.Graphics.TranslateTransform(-Left, -Top);
                    var pe = new PaintEventArgs(e.Graphics, new Rectangle(Left, Top, Width, Height));
                    InvokePaintBackground(Parent, pe);
                    InvokePaint(Parent, pe);
                }
                finally
                {
                    e.Graphics.Restore(state);
                }
            }
            else
            {
                base.OnPaintBackground(e);
            }
        }

        /// <inheritdoc />
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            var rect = this.ClientRectangle;
            if (rect.Width <= 0 || rect.Height <= 0)
                return;

            var innerBorder = new Rectangle(rect.X, rect.Y, rect.Width - 1, rect.Height - 1);
            var innerValue = new Rectangle(rect.X + 1, rect.Y + 1, rect.Width - 2, rect.Height - 2);

            // 1) Semi-transparent background of unfilled area
            int alpha = (int)Math.Round(255.0 * (100 - BackgroundTransparencyPercent) / 100.0); // 0..255
            using (var bg = new SolidBrush(Color.FromArgb(alpha, BarBackgroundColor)))
            {
                g.FillRectangle(bg, innerValue);
            }

            // 2) Filled portion with gradient — guard against zero-sized rectangles
            if (Maximum > 0 && Value > 0)
            {
                float ratio = Math.Min(1f, Math.Max(0f, (float)Value / Maximum));
                if (ratio > 0f)
                {
                    Rectangle fillArea = Rectangle.Empty;

                    if (Orientation == OrientationEnum.Horizontal)
                    {
                        int w = (int)Math.Round(innerValue.Width * ratio);
                        if (w > 0)
                            fillArea = new Rectangle(innerValue.X, innerValue.Y, w, innerValue.Height);
                    }
                    else
                    {
                        int h = (int)Math.Round(innerValue.Height * ratio);
                        if (h > 0)
                            fillArea = new Rectangle(innerValue.X, innerValue.Bottom - h, innerValue.Width, h);
                    }

                    // Only create LinearGradientBrush when both dimensions are positive
                    if (!fillArea.IsEmpty && fillArea.Width > 0 && fillArea.Height > 0)
                    {
                        float angle = (Orientation == OrientationEnum.Horizontal) ? 0f : 90f; // 0 = left→right, 90 = vertical
                        using (var brush = new LinearGradientBrush(fillArea, GradientStartColor, GradientEndColor, angle))
                        {
                            var blend = new ColorBlend
                            {
                                Positions = new[] { 0f, 0.5f, 1f },
                                Colors = new[] { GradientStartColor, Mix(GradientStartColor, GradientEndColor, 0.5f), GradientEndColor }
                            };
                            brush.InterpolationColors = blend;
                            g.FillRectangle(brush, fillArea);
                        }
                    }
                }
            }

            // 3) Border
            if (BorderStyle == BorderStyleEnum.Solid)
            {
                using (var pen = new Pen(SystemColors.ControlDarkDark))
                    g.DrawRectangle(pen, innerBorder);
            }

            // 4) Text
            if (DisplayTextType == DisplayTextTypeEnum.CustomText && !string.IsNullOrEmpty(CustomText))
            {
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
                float angleDeg = (TextAngle == TextAngleEnum.Vertical) ? -90f : 0f;
                using (var font = (Font)CustomTextFont.Clone())
                using (var brush = new SolidBrush(CustomTextColor))
                {
                    DrawCenteredText(g, CustomText, font, brush, rect, angleDeg);
                }
            }
        }

        /// <summary>Draws a string centered (and optionally rotated) within a rectangle.</summary>
        /// <remarks>Uses <see cref="Graphics.TranslateTransform(float,float)"/> and <see cref="Graphics.RotateTransform(float)"/>.</remarks>
        /// <param name="g">Graphics surface.</param>
        /// <param name="text">Text to render.</param>
        /// <param name="font">Font to use.</param>
        /// <param name="brush">Brush to draw the text.</param>
        /// <param name="bounds">Control-relative bounds.</param>
        /// <param name="angleDegrees">Clockwise rotation angle.</param>
        /// <example>
        /// <code>
        /// DrawCenteredText(e.Graphics, "Ready", this.Font, Brushes.Black, this.ClientRectangle, 0f);
        /// </code>
        /// </example>
        public void DrawCenteredText(Graphics g, string text, Font font, Brush brush, Rectangle bounds, float angleDegrees)
        {
            if (string.IsNullOrEmpty(text)) return;
            SizeF size = g.MeasureString(text, font);
            var state = g.Save();
            try
            {
                g.TranslateTransform(bounds.X + bounds.Width / 2f, bounds.Y + bounds.Height / 2f);
                g.RotateTransform(angleDegrees);
                g.DrawString(text, font, brush, -size.Width / 2f, -size.Height / 2f);
            }
            finally
            {
                g.Restore(state);
            }
        }

        /// <summary>Linear interpolation between two colors.</summary>
        /// <param name="a">Start color.</param>
        /// <param name="b">End color.</param>
        /// <param name="t">Interpolation factor in [0,1].</param>
        /// <returns>Mixed color.</returns>
        private static Color Mix(Color a, Color b, float t)
        {
            t = Math.Max(0f, Math.Min(1f, t));
            return Color.FromArgb(
                (int)(a.A + (b.A - a.A) * t),
                (int)(a.R + (b.R - a.R) * t),
                (int)(a.G + (b.G - a.G) * t),
                (int)(a.B + (b.B - a.B) * t));
        }

        /// <summary>Clamp helper.</summary>
        private static int Clamp(int v, int min, int max)
        {
            if (v < min) return min;
            if (v > max) return max;
            return v;
        }
    }


}