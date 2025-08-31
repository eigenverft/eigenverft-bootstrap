using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Text;
using System.Windows.Forms;

namespace Eigenverft.Bootstrapper
{
    public class PanelEx : Panel
    {
        protected override CreateParams CreateParams
        {
            get
            {
                const int CS_DROPSHADOW = 0x20000;
                var cp = base.CreateParams;
                cp.ClassStyle |= CS_DROPSHADOW;
                return cp;
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var rect = ClientRectangle;
            using (var path = CreateRoundedPath(rect))
            using (var brush = new SolidBrush(BackColor))
            {
                Region = new Region(path);
                e.Graphics.FillPath(brush, path);
                Rectangle picrec = new Rectangle(0, 0, BackgroundImage.Width, BackgroundImage.Height);
                e.Graphics.DrawImage(BackgroundImage, picrec);
            }
        }

        private GraphicsPath CreateRoundedPath(Rectangle rect, int cornerRadius = 8)
        {
            var path = new GraphicsPath();
            path.AddArc(rect.X, rect.Y, cornerRadius * 2, cornerRadius * 2, 180, 90);
            path.AddLine(rect.X + cornerRadius, rect.Y, rect.Right - cornerRadius, rect.Y);
            path.AddArc(rect.Right - cornerRadius * 2, rect.Y, cornerRadius * 2, cornerRadius * 2, 270, 90);
            path.AddLine(rect.Right, rect.Y + cornerRadius, rect.Right, rect.Bottom - cornerRadius);
            path.AddArc(rect.Right - cornerRadius * 2, rect.Bottom - cornerRadius * 2, cornerRadius * 2, cornerRadius * 2, 0, 90);
            path.AddLine(rect.Right - cornerRadius, rect.Bottom, rect.X + cornerRadius, rect.Bottom);
            path.AddArc(rect.X, rect.Bottom - cornerRadius * 2, cornerRadius * 2, cornerRadius * 2, 90, 90);
            path.AddLine(rect.X, rect.Bottom - cornerRadius, rect.X, rect.Y + cornerRadius);
            path.CloseFigure();
            return path;
        }
    }
}
