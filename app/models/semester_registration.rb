class SemesterRegistration < ApplicationRecord
	after_save :change_course_registration_status
	after_save :assign_section_to_course_registration
	after_create :semester_course_registration
	after_save :generate_invoice
	##validations
	  # validates :semester, :presence => true
		# validates :year, :presence => true
	##scope
  	scope :recently_added, lambda { where('created_at >= ?', 1.week.ago)}
  	scope :undergraduate, lambda { where(study_level: "undergraduate")}
  	scope :graduate, lambda { where(study_level: "graduate")}
  	scope :online, lambda { where(admission_type: "online")}
  	scope :regular, lambda { where(admission_type: "regular")}
  	scope :extention, lambda { where(admission_type: "extention")}
  	scope :distance, lambda { where(admission_type: "distance")}
	##associations
	  belongs_to :student
	  belongs_to :program
	  belongs_to :department
	  belongs_to :section, optional: true
	  belongs_to :academic_calendar
	  has_many :course_registrations, dependent: :destroy
  	has_many :courses, through: :course_registrations, dependent: :destroy
  	accepts_nested_attributes_for :course_registrations, reject_if: :all_blank, allow_destroy: true
  	has_many :invoices, dependent: :destroy
  	has_one :grade_report, dependent: :destroy
  	has_many :recurring_payments, dependent: :destroy
  	has_many :add_and_drops, dependent: :destroy

  	def generate_grade_report
  		if !self.grade_report.present?
	  		GradeReport.create do |report|
	  			report.semester_registration_id = self.id
					report.student_id = self.student.id
					report.academic_calendar_id = self.academic_calendar.id
		  		report.program_id = self.program.id
					report.department_id = self.program.department.id
					# grade_report.section_id = self.section.id
					report.admission_type = self.student.admission_type
					report.study_level = self.student.study_level
					report.semester= self.student.semester
					report.year= self.student.year
					# grade_report.total_course = self.course_registrations.where(enrollment_status: "enrolled").count
					

					if self.student.grade_reports.empty?
						report.total_course = self.course_registrations.count
						report.total_credit_hour = self.course_registrations.where(enrollment_status: "enrolled").collect { |oi| ((oi.student_grade.letter_grade != "I") && (oi.student_grade.letter_grade != "NG")) ? (oi.course.credit_hour) : 0 }.sum 
						report.total_grade_point = self.course_registrations.where(enrollment_status: "enrolled").collect { |oi| ((oi.student_grade.letter_grade != "I") && (oi.student_grade.letter_grade != "NG")) ? (oi.student_grade.grade_point) : 0 }.sum 
						report.sgpa = report.total_credit_hour == 0 ? 0 : (report.total_grade_point / report.total_credit_hour).round(1) 

						report.cumulative_total_credit_hour = report.total_credit_hour
						report.cumulative_total_grade_point = report.total_grade_point
						report.cgpa = report.cumulative_total_credit_hour == 0 ? 0 : (report.cumulative_total_grade_point / report.cumulative_total_credit_hour).round(1)

						if ((self.course_registrations.joins(:student_grade).pluck(:letter_grade).include?("I")) || (self.course_registrations.joins(:student_grade).pluck(:letter_grade).include?("NG")))
							report.academic_status = "Incomplete"
						else
							report.academic_status = self.student.program.grade_systems.last.academic_statuses.where("min_value < ?", report.cgpa).where("max_value > ?", report.cgpa).last.status
							if (report.academic_status != "Dismissal") || (report.academic_status != "Incomplete")
								if self.program.program_semester > self.student.semester
									promoted_semester = self.student.semester + 1
									self.student.update_columns(semester: promoted_semester)
								elsif (self.program.program_semester == self.student.semester) && (self.program.program_duration > self.student.year)
									promoted_year = self.student.year + 1
									self.student.update_columns(semester: 1)
									self.student.update_columns(year: promoted_year)
								end
							end
						end
					elsif self.student.grade_reports.present?
						report.total_course = self.course_registrations.count
						report.total_credit_hour = self.course_registrations.collect { |oi| ((oi.student_grade.letter_grade != "I") && (oi.student_grade.letter_grade != "NG")) ? (oi.course.credit_hour) : 0 }.sum 
						report.total_grade_point = self.course_registrations.collect { |oi| ((oi.student_grade.letter_grade != "I") && (oi.student_grade.letter_grade != "NG")) ? (oi.course.credit_hour * oi.student_grade.grade_point) : 0 }.sum 
						report.sgpa = report.total_credit_hour == 0 ? 0 : (report.total_grade_point / report.total_credit_hour).round(1) 
						report.cumulative_total_credit_hour = self.student.grade_reports.order("created_at DESC").first.cumulative_total_credit_hour + report.total_credit_hour
						report.cumulative_total_grade_point = self.student.grade_reports.order("created_at DESC").first.cumulative_total_grade_point + report.total_grade_point
						report.cgpa = report.cumulative_total_grade_point / report.cumulative_total_credit_hour
						if ((self.course_registrations.joins(:student_grade).pluck(:letter_grade).include?("I")) || (self.course_registrations.joins(:student_grade).pluck(:letter_grade).include?("NG")))
							report.academic_status = "Incomplete"
						else
							report.academic_status = self.student.program.grade_systems.last.academic_statuses.where("min_value <= ?", report.cgpa).where("max_value >= ?", report.cgpa).last.status
							if (report.academic_status != "Dismissal") || (report.academic_status != "Incomplete")
								if self.program.program_semester > self.student.semester
									promoted_semester = self.student.semester + 1
									self.student.update_columns(semester: promoted_semester)
								elsif (self.program.program_semester == self.student.semester) && (self.program.program_duration > self.student.year)
									promoted_year = self.student.year + 1
									self.student.update_columns(semester: 1)
									self.student.update_columns(year: promoted_year)
								end
							end
						end
					end
					
					report.created_by = self.created_by			
				end
			end
  	end
  	private	
	  	def generate_invoice
	  		if self.mode_of_payment.present? && self.invoices.where(year: self.year, semester: self.semester).empty?
	  			Invoice.create do |invoice|
	  				invoice.semester_registration_id = self.id
	  				invoice.student_id = self.student.id
						invoice.department_id = self.department_id
						invoice.program_id = self.program_id
	  				invoice.academic_calendar_id = self.academic_calendar_id
	  				invoice.year = self.year
	  				invoice.semester = self.semester
		  			invoice.student_id_number = self.student_id_number
		  			invoice.student_full_name = self.student_full_name
	  				invoice.created_by = self.last_updated_by
	  				invoice.due_date = self.created_at + 10.day 
	  				invoice.invoice_status = "unpaid"
						# invoice.registration_fee = CollegePayment.where(study_level: self.study_level,admission_type: self.admission_type).first.pluck(:registration_fee)

						if Activity.where(category: "registration", academic_calendar_id: AcademicCalendar.where(study_level: self.study_level, admission_type: self.admission_type).where("starting_date <= ? AND ending_date >= ?",Time.zone.now, Time.zone.now).order("created_at DESC").first).where("starting_date <= ? AND ending_date >= ?",Time.zone.now, Time.zone.now).order("created_at DESC").first

								invoice.registration_fee = CollegePayment.where(study_level: self.study_level,admission_type: self.admission_type).first.registration_fee

						elsif Activity.where(category: "late registration", academic_calendar_id: AcademicCalendar.where(study_level: self.study_level, admission_type: self.admission_type).where("starting_date <= ? AND ending_date >= ?",Time.zone.now, Time.zone.now).order("created_at DESC").first).where("starting_date <= ? AND ending_date >= ?",Time.zone.now, Time.zone.now).order("created_at DESC").first

								invoice.late_registration_fee = CollegePayment.where(study_level: self.study_level,admission_type: self.admission_type).pluck(:late_registration_fee).first
						end

						invoice.invoice_number = SecureRandom.random_number(10000000)
						if mode_of_payment == "Monthly Payment"
							tution_price = (self.course_registrations.collect { |oi| oi.valid? ? (CollegePayment.where(study_level: self.study_level,admission_type: self.admission_type).first.tution_per_credit_hr * oi.course.credit_hour) : 0 }.sum) /4 
							invoice.total_price = tution_price + invoice.registration_fee + invoice.late_registration_fee
						elsif mode_of_payment == "Full Semester Payment"
							tution_price = (self.course_registrations.collect { |oi| oi.valid? ? (CollegePayment.where(study_level: self.study_level,admission_type: self.admission_type).first.tution_per_credit_hr * oi.course.credit_hour) : 0 }.sum)
							invoice.total_price = tution_price + invoice.registration_fee + invoice.late_registration_fee
						elsif mode_of_payment == "Half Semester Payment"
							tution_price = (self.course_registrations.collect { |oi| oi.valid? ? (CollegePayment.where(study_level: self.study_level,admission_type: self.admission_type).first.tution_per_credit_hr * oi.course.credit_hour) : 0 }.sum) /2 
							invoice.total_price = tution_price + invoice.registration_fee + invoice.late_registration_fee
						end	
						
						# self.total_price = (self.course_registrations.collect { |oi| oi.valid? ? (CollegePayment.where(study_level: self.study_level,admission_type: self.admission_type).first.tution_per_credit_hr * oi.curriculum.credit_hour) : 0 }.sum) + CollegePayment.where(study_level: self.study_level,admission_type: self.admission_type).first.registration_fee
	  			end
	  		end
	  	end
	  	def semester_course_registration
		  	self.program.curriculums.where(curriculum_version: self.student.curriculum_version).last.courses.where(year: self.year, semester: self.semester).each do |co|
		  		CourseRegistration.create do |course_registration|
		  			course_registration.semester_registration_id = self.id
		  			course_registration.program_id = self.program.id
		  			course_registration.department_id = self.department.id
		  			course_registration.academic_calendar_id = self.academic_calendar_id
		  			course_registration.student_id = self.student.id
		  			course_registration.student_full_name = self.student_full_name
		  			course_registration.course_id = co.id
		  			course_registration.course_title = co.course_title
		  			course_registration.semester = self.semester
						course_registration.year = self.year
		  			# course_registration.course_section_id = CourseSection.first.id
		  			course_registration.created_by = self.created_by
				  end
				end
	  	end

	  	def change_course_registration_status
	  		if (self.registrar_approval_status == "approved")
	  			self.course_registrations.where(enrollment_status: "pending").map{|course| course.update_columns(enrollment_status: "enrolled")}
	  		end
	  	end

	  	def assign_section_to_course_registration
	  		if (self.registrar_approval_status == "approved") && self.section.present? 
	  			self.course_registrations.where(section_id: nil).map{|course| course.update(section_id: self.section_id)}
	  		end
	  	end
end
