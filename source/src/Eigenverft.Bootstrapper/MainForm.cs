using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Windows.Forms;

namespace Eigenverft.Bootstrapper
{
    public partial class MainForm : Form
    {
        private readonly BackgroundWorker _worker;

        public MainForm()
        {
            InitializeComponent();

            _worker = new BackgroundWorker
            {
                WorkerReportsProgress = true,
                WorkerSupportsCancellation = false
            };
            _worker.DoWork += Worker_DoWork;
            _worker.ProgressChanged += Worker_ProgressChanged;
            _worker.RunWorkerCompleted += Worker_RunWorkerCompleted;

        }

        private void MainForm_Shown(object sender, EventArgs e)
        {
            progressBarEx31.CustomText = "Starting...";
            _worker.RunWorkerAsync(progressBarEx31.Maximum);
        }

        /// <summary>Performs the long-running work off the UI thread.</summary>
        /// <remarks>Reports progress via <see cref="BackgroundWorker.ReportProgress(int)"/>.</remarks>
        /// <param name="sender">The worker instance.</param>
        /// <param name="e">Argument holds the maximum value.</param>
        private void Worker_DoWork(object sender, DoWorkEventArgs e)
        {
            var max = (int)e.Argument;
            var bw = (BackgroundWorker)sender;

            for (int i = 0; i <= max; i++)
            {
                System.Threading.Thread.Sleep(20); // simulate work
                bw.ReportProgress(i);
            }
        }

        /// <summary>Updates the progress bar on the UI thread.</summary>
        /// <param name="sender">The worker instance.</param>
        /// <param name="e">Progress percentage used as the bar value.</param>
        private void Worker_ProgressChanged(object sender, ProgressChangedEventArgs e)
        {
            // Reviewer note: avoid forcing .Update(); just set Value and your custom text.
            progressBarEx31.Value = e.ProgressPercentage;
            progressBarEx31.CustomText = e.ProgressPercentage.ToString()+"/"+progressBarEx31.Maximum.ToString();
        }

        /// <summary>Closes the form when the work completes (or errors).</summary>
        /// <param name="sender">The worker instance.</param>
        /// <param name="e">Completion args; check <see cref="RunWorkerCompletedEventArgs.Error"/> for failures.</param>
        /// <example>
        /// <code>
        /// // Add logging if needed:
        /// // if (e.Error != null) Log(e.Error);
        /// </code>
        /// </example>
        private void Worker_RunWorkerCompleted(object sender, RunWorkerCompletedEventArgs e)
        {
            // Optional: handle e.Error / e.Cancelled here.
            this.Close();
        }
    }
}