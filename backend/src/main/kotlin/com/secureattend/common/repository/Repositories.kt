package com.secureattend.common.repository

import com.secureattend.common.entity.*
import org.springframework.data.domain.Page
import org.springframework.data.domain.Pageable
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import org.springframework.stereotype.Repository
import java.util.UUID

@Repository
interface UserRepository : JpaRepository<User, UUID> {
    fun findByEmail(email: String): User?
    fun existsByEmail(email: String): Boolean
    fun findByUsername(username: String): User?
    fun existsByUsername(username: String): Boolean
    fun findByRole(role: UserRole, pageable: Pageable): Page<User>
    fun findByStatus(status: UserStatus, pageable: Pageable): Page<User>
    fun findByRole(role: UserRole): List<User>
    fun findByRoleAndStatus(role: UserRole, status: UserStatus): List<User>
    fun findByRoleAndStatusAndBranch(role: UserRole, status: UserStatus, branch: String): List<User>

    @Query("""
        SELECT u FROM User u 
        WHERE (:role IS NULL OR u.role = :role)
          AND (:status IS NULL OR u.status = :status)
          AND (:branch IS NULL OR u.branch = :branch)
          AND (:semester IS NULL OR u.semester = :semester)
          AND (:search IS NULL OR LOWER(u.fullName) LIKE LOWER(CONCAT('%', :search, '%')) 
               OR LOWER(u.email) LIKE LOWER(CONCAT('%', :search, '%'))
               OR LOWER(COALESCE(u.username, '')) LIKE LOWER(CONCAT('%', :search, '%'))
               OR LOWER(COALESCE(u.rollNo, '')) LIKE LOWER(CONCAT('%', :search, '%')))
    """)
    fun filterUsers(
        @Param("role") role: UserRole?,
        @Param("status") status: UserStatus?,
        @Param("branch") branch: String?,
        @Param("semester") semester: Int?,
        @Param("search") search: String?,
        pageable: Pageable
    ): Page<User>

    @Query("SELECT u FROM User u WHERE u.role = :role AND (LOWER(u.fullName) LIKE LOWER(CONCAT('%', :search, '%')) OR LOWER(u.email) LIKE LOWER(CONCAT('%', :search, '%')))")
    fun searchByRoleAndNameOrEmail(@Param("role") role: UserRole, @Param("search") search: String, pageable: Pageable): Page<User>
}

@Repository
interface CourseRepository : JpaRepository<Course, UUID> {
    fun findByCode(code: String): Course?
    fun existsByCode(code: String): Boolean
    fun findByFacultyIdAndIsActiveTrue(facultyId: UUID): List<Course>

    @Query("""
        SELECT c FROM Course c 
        WHERE (:branch IS NULL OR c.branch = :branch)
          AND (:facultyId IS NULL OR c.facultyId = :facultyId)
          AND (:semester IS NULL OR c.semester = :semester)
          AND (:academicSession IS NULL OR c.academicSession = :academicSession)
          AND (:isActive IS NULL OR c.isActive = :isActive)
          AND (:search IS NULL OR LOWER(c.code) LIKE LOWER(CONCAT('%', :search, '%')) OR LOWER(c.name) LIKE LOWER(CONCAT('%', :search, '%')))
    """)
    fun filterCourses(
        @Param("branch") branch: String?,
        @Param("facultyId") facultyId: UUID?,
        @Param("semester") semester: Int?,
        @Param("academicSession") academicSession: String?,
        @Param("isActive") isActive: Boolean?,
        @Param("search") search: String?,
        pageable: Pageable
    ): Page<Course>

    @Query("SELECT c FROM Course c WHERE LOWER(c.code) LIKE LOWER(CONCAT('%', :search, '%')) OR LOWER(c.name) LIKE LOWER(CONCAT('%', :search, '%'))")
    fun search(@Param("search") search: String, pageable: Pageable): Page<Course>
}

@Repository
interface CourseEnrollmentRepository : JpaRepository<CourseEnrollment, CourseEnrollmentId> {
    fun findByIdCourseId(courseId: UUID): List<CourseEnrollment>
    fun findByIdStudentId(studentId: UUID): List<CourseEnrollment>
    fun existsByIdStudentIdAndIdCourseId(studentId: UUID, courseId: UUID): Boolean
    fun countByIdCourseId(courseId: UUID): Long
}

@Repository
interface DeviceRegistrationRepository : JpaRepository<DeviceRegistration, UUID> {
    fun findByStudentIdAndIsActiveTrue(studentId: UUID): DeviceRegistration?
    fun existsByStudentIdAndIsActiveTrue(studentId: UUID): Boolean
}

@Repository
interface FaceEmbeddingRepository : JpaRepository<FaceEmbedding, UUID> {
    fun findByStudentId(studentId: UUID): FaceEmbedding?
    fun existsByStudentId(studentId: UUID): Boolean
}

@Repository
interface SessionRepository : JpaRepository<Session, UUID> {
    fun findByStatus(status: SessionStatus): List<Session>
    fun findByCourseIdAndStatus(courseId: UUID, status: SessionStatus): Session?
    fun findByFacultyId(facultyId: UUID, pageable: Pageable): Page<Session>
    fun findByFacultyIdAndStatus(facultyId: UUID, status: SessionStatus, pageable: Pageable): Page<Session>
    fun findByCourseId(courseId: UUID, pageable: Pageable): Page<Session>
}

@Repository
interface ScanRepository : JpaRepository<Scan, UUID> {
    fun findBySessionId(sessionId: UUID, pageable: Pageable): Page<Scan>
    fun findBySessionIdAndFinalStatus(sessionId: UUID, status: ScanStatus, pageable: Pageable): Page<Scan>
    fun findByStudentId(studentId: UUID): List<Scan>

    @Query("SELECT s FROM Scan s WHERE s.sessionId = :sessionId AND s.studentId = :studentId AND s.finalStatus IN ('PRESENT', 'FLAGGED')")
    fun findAcceptedScan(@Param("sessionId") sessionId: UUID, @Param("studentId") studentId: UUID): Scan?

    @Query("SELECT COUNT(s) FROM Scan s WHERE s.sessionId = :sessionId AND s.finalStatus = 'PRESENT'")
    fun countPresent(@Param("sessionId") sessionId: UUID): Long

    @Query("SELECT COUNT(s) FROM Scan s WHERE s.sessionId = :sessionId AND s.finalStatus = 'FLAGGED'")
    fun countFlagged(@Param("sessionId") sessionId: UUID): Long

    @Query("SELECT COUNT(s) FROM Scan s WHERE s.sessionId = :sessionId AND s.finalStatus = 'REJECTED'")
    fun countRejected(@Param("sessionId") sessionId: UUID): Long

    @Query("SELECT COUNT(s) FROM Scan s WHERE s.sessionId = :sessionId")
    fun countTotal(@Param("sessionId") sessionId: UUID): Long
}

@Repository
interface ScanLayerResultRepository : JpaRepository<ScanLayerResult, UUID> {
    fun findByScanId(scanId: UUID): List<ScanLayerResult>
}

@Repository
interface ReviewQueueRepository : JpaRepository<ReviewQueueEntry, UUID> {
    fun findByScanId(scanId: UUID): ReviewQueueEntry?

    @Query("SELECT r FROM ReviewQueueEntry r WHERE r.reviewDecision IS NULL ORDER BY r.flaggedAt DESC")
    fun findPending(pageable: Pageable): Page<ReviewQueueEntry>

    @Query("SELECT r FROM ReviewQueueEntry r JOIN Scan s ON r.scanId = s.id WHERE s.sessionId = :sessionId AND r.reviewDecision IS NULL ORDER BY r.flaggedAt DESC")
    fun findPendingBySession(@Param("sessionId") sessionId: UUID, pageable: Pageable): Page<ReviewQueueEntry>
}
