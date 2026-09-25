Gixbee jobseeker (employee) job profile — HTML demo
====================================================

OPEN THIS FILE IN A BROWSER
  docs/prototypes/jobseeker-job-profile-master.html

Branch (must contain the file):
  cursor/hire-employee-html-flow-b579

DO NOT OPEN
  seeker-job-profile-shell.html   (empty until regenerated)

If the screen is blank or sectors never load
  1. Hard refresh: Ctrl+Shift+R (Mac: Cmd+Shift+R)
  2. Serve over HTTP (some previews block file://):
       cd docs/prototypes
       python3 -m http.server 8765
     Then open http://localhost:8765/jobseeker-job-profile-master.html

Regenerate after editing JS/shell:
  python3 docs/prototypes/_gen_seeker_profile_html.py

18-sector detailed PDF (jobseeker, same positions as HTML):
  docs/prototypes/GIXBEE_Jobseeker_Job_Profile_Catalog_18_Sectors.pdf

Regenerate PDF:
  python3 docs/prototypes/_gen_hire_catalog_pdf.py

Employer (hire) demo:
  docs/prototypes/hire-employee-skills-master.html

Employer PDF (same catalogue data):
  docs/prototypes/GIXBEE_Hire_Employee_Catalog_18_Sectors.pdf
