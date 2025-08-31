using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace Eigenverft.Bootstrapper.Extensions
{
    /// <summary>
    /// Provides extension methods to make WinForms controls draggable by mouse.
    /// </summary>
    public static partial class ControlExtensions
    {
        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        public const int WM_NCLBUTTONDOWN = 0xA1;
        public static readonly IntPtr HT_CAPTION = new IntPtr(0x2);

        /// <summary>
        /// Registers the control’s <c>MouseDown</c> event to enable dragging of the parent form.
        /// </summary>
        /// <remarks>
        /// This method wires up the necessary native calls to allow moving the form when the user clicks and drags the control.
        /// </remarks>
        /// <param name="control">The control that will act as the drag handle.</param>
        /// <param name="formHandle">The window handle (<c>IntPtr</c>) of the form to be dragged.</param>
        /// <example>
        /// <code>
        /// // In your form's constructor:
        /// this.headerPanel.EnableDrag(this.Handle);
        /// </code>
        /// </example>
        public static void EnableDrag(this Control control, IntPtr formHandle)
        {
            control.MouseDown += (sender, e) => OnControlMouseDown(sender, e, formHandle);
        }

        /// <summary>
        /// Handles the <c>MouseDown</c> event, initiating the drag operation for the form.
        /// </summary>
        /// <param name="sender">The source of the mouse event.</param>
        /// <param name="e">Mouse event arguments.</param>
        /// <param name="formHandle">The handle of the form to drag.</param>
        private static void OnControlMouseDown(object sender, MouseEventArgs e, IntPtr formHandle)
        {
            if (e.Button == MouseButtons.Left)
            {
                ReleaseCapture();
                SendMessage(
                    formHandle,
                    WM_NCLBUTTONDOWN,
                    HT_CAPTION,
                    IntPtr.Zero);
            }
        }
    }
}
