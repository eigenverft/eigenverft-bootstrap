using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;

namespace Eigenverft.Bootstrapper
{


    public class TransparentLabelEx3 : Label
    {
        private Color startColor = Color.White;
        private Color endColor = Color.LightGray;
        private float gradientAngle = 0f;

        private bool shadowEnabled = false;
        private Color shadowColor = Color.Gray;
        private Point shadowOffset = new Point(1, 1);

        private bool fullShadowEnabled = false;
        private Color fullShadowColor = Color.FromArgb(128, 0, 0, 0); // semi-transparent black
        private int fullShadowDepth = 1;

        /// <summary>First color of the linear gradient for the text.</summary>
        [Category("AppearanceExtended")]
        [Description("First color of the linear gradient for the text.")]
        public Color StartColor
        {
            get { return startColor; }
            set { startColor = value; Invalidate(); }
        }

        /// <summary>Second color of the linear gradient for the text.</summary>
        [Category("AppearanceExtended")]
        [Description("Second color of the linear gradient for the text.")]
        public Color EndColor
        {
            get { return endColor; }
            set { endColor = value; Invalidate(); }
        }

        /// <summary>Angle of the linear gradient in degrees.</summary>
        [Category("AppearanceExtended")]
        [Description("Angle of the linear gradient in degrees.")]
        public float GradientAngle
        {
            get { return gradientAngle; }
            set { gradientAngle = value; Invalidate(); }
        }

        /// <summary>Enables or disables a single directional text shadow.</summary>
        [Category("AppearanceExtended")]
        [Description("Enables or disables a single directional text shadow.")]
        public bool ShadowEnabled
        {
            get { return shadowEnabled; }
            set { shadowEnabled = value; Invalidate(); }
        }

        /// <summary>Color used for the single directional text shadow.</summary>
        [Category("AppearanceExtended")]
        [Description("Color used for the single directional text shadow.")]
        public Color ShadowColor
        {
            get { return shadowColor; }
            set { shadowColor = value; Invalidate(); }
        }

        /// <summary>Offset for the single directional text shadow.</summary>
        [Category("AppearanceExtended")]
        [Description("Offset for the single directional text shadow.")]
        public Point ShadowOffset
        {
            get { return shadowOffset; }
            set { shadowOffset = value; Invalidate(); }
        }

        /// <summary>Enables or disables a full eight-directional text shadow.</summary>
        [Category("AppearanceExtended")]
        [Description("Enables or disables a full eight-directional text shadow.")]
        public bool FullShadowEnabled
        {
            get { return fullShadowEnabled; }
            set { fullShadowEnabled = value; Invalidate(); }
        }

        /// <summary>Color used for the full eight-directional text shadow (supports alpha).</summary>
        [Category("AppearanceExtended")]
        [Description("Color used for the full eight-directional text shadow (supports alpha).")]
        public Color FullShadowColor
        {
            get { return fullShadowColor; }
            set { fullShadowColor = value; Invalidate(); }
        }

        /// <summary>Distance in pixels for each direction in the full shadow.</summary>
        [Category("AppearanceExtended")]
        [Description("Distance in pixels for each direction in the full shadow.")]
        public int FullShadowDepth
        {
            get { return fullShadowDepth; }
            set { fullShadowDepth = value; Invalidate(); }
        }

        public TransparentLabelEx3()
        {
            SetStyle(
                ControlStyles.SupportsTransparentBackColor |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.UserPaint,
                true);
            BackColor = Color.Transparent;
            ForeColor = Color.Black;
        }

        /// <summary>Draws the text with optional shadows and a linear gradient.</summary>
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

            StringFormat sf = CreateStringFormat();

            // single shadow
            if (ShadowEnabled)
            {
                using (SolidBrush brush = new SolidBrush(ShadowColor))
                {
                    Rectangle rect = new Rectangle(
                        ClientRectangle.X + ShadowOffset.X,
                        ClientRectangle.Y + ShadowOffset.Y,
                        ClientRectangle.Width,
                        ClientRectangle.Height);
                    e.Graphics.DrawString(Text, Font, brush, rect, sf);
                }
            }

            // full shadow
            if (FullShadowEnabled)
            {
                using (SolidBrush brush = new SolidBrush(FullShadowColor))
                {
                    Point[] dirs = new Point[]
                    {
                    new Point(-1, -1), new Point(0, -1), new Point(1, -1),
                    new Point(-1,  0),                  new Point(1,  0),
                    new Point(-1,  1), new Point(0,  1), new Point(1,  1)
                    };
                    foreach (Point d in dirs)
                    {
                        Rectangle rect = new Rectangle(
                            ClientRectangle.X + d.X * FullShadowDepth,
                            ClientRectangle.Y + d.Y * FullShadowDepth,
                            ClientRectangle.Width,
                            ClientRectangle.Height);
                        e.Graphics.DrawString(Text, Font, brush, rect, sf);
                    }
                }
            }

            // gradient text
            using (LinearGradientBrush brush = new LinearGradientBrush(ClientRectangle, StartColor, EndColor, GradientAngle))
            {
                e.Graphics.DrawString(Text, Font, brush, ClientRectangle, sf);
            }
        }

        private StringFormat CreateStringFormat()
        {
            StringFormat sf = new StringFormat();

            switch (TextAlign)
            {
                case ContentAlignment.TopCenter:
                case ContentAlignment.MiddleCenter:
                case ContentAlignment.BottomCenter:
                    sf.Alignment = StringAlignment.Center;
                    break;

                case ContentAlignment.TopRight:
                case ContentAlignment.MiddleRight:
                case ContentAlignment.BottomRight:
                    sf.Alignment = StringAlignment.Far;
                    break;

                default:
                    sf.Alignment = StringAlignment.Near;
                    break;
            }

            switch (TextAlign)
            {
                case ContentAlignment.MiddleLeft:
                case ContentAlignment.MiddleCenter:
                case ContentAlignment.MiddleRight:
                    sf.LineAlignment = StringAlignment.Center;
                    break;

                case ContentAlignment.BottomLeft:
                case ContentAlignment.BottomCenter:
                case ContentAlignment.BottomRight:
                    sf.LineAlignment = StringAlignment.Far;
                    break;

                default:
                    sf.LineAlignment = StringAlignment.Near;
                    break;
            }

            return sf;
        }
    }

}