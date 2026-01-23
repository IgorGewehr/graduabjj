# Comparativo WebApp vs Flutter App - GraduaBJJ

## Resumo Executivo

| Categoria | WebApp | Flutter | Status |
|-----------|--------|---------|--------|
| Serviços | 15 | 13 | 87% |
| Métodos CRUD | ~150 | ~60 | 40% |
| Hooks/Providers | 12 hooks | 35 providers | Parcial |

---

## 1. StudentService - Lista de Alunos

### WebApp (Completo)
```
✓ listAll(filters, pageSize, lastStudentId) - Paginação infinita
✓ searchByName(searchTerm, filters) - Busca com filtros
✓ list(filters, page, perPage) - Paginação padrão
✓ getById(id)
✓ getByStatus(status)
✓ getActive()
✓ getAll() - Para relatórios
✓ search(searchTerm)
✓ create(student, createdBy)
✓ update(id, data)
✓ delete(id) - Soft delete
✓ hardDelete(id)
✓ quickCreate(fullName, phone, createdBy)
✓ getByBelt(belt)
✓ getByCategory(category)
✓ getCountByStatus()
✓ getDashboardStats()
✓ updateBelt(id, newBelt, newStripes)
✓ syncAttendanceCounts()
```

### Flutter (Incompleto)
```
✓ getById(id)
✓ getByLinkedUserId(userId)
✓ listAll(filters) - SEM paginação infinita
✓ getActive()
✓ getByStatus(status)
✓ getByCategory(category)
✓ getByBelt(belt)
✓ searchByName(searchTerm, filters)
✓ getDashboardStats()
✓ update(id, data)
✓ updateBelt(id, newBelt, newStripes)
✓ updatePhotoUrl(id, photoUrl)
✓ linkToUser(studentId, userId)
✓ unlinkFromUser(studentId)

✗ create() - FALTANDO
✗ delete() - FALTANDO
✗ hardDelete() - FALTANDO
✗ quickCreate() - FALTANDO
✗ getAll() - FALTANDO (relatórios)
✗ syncAttendanceCounts() - FALTANDO
✗ Paginação infinita - FALTANDO
✗ Filtro por paymentStatus - FALTANDO
```

**Gap: 35% funcionalidade faltando**

---

## 2. AttendanceService - Chamada de Alunos

### WebApp (Completo)
```
✓ getByDateAndClass(date, classId)
✓ getTodayByClass(classId)
✓ getByStudent(studentId, limit)
✓ getByDateRange(startDate, endDate, filters)
✓ isStudentPresent(studentId, classId, date)
✓ getPresentStudentIds(classId, date)
✓ markPresent(studentId, studentName, classId, className, verifiedBy, verifiedByName, date, notes)
✓ unmarkPresent(studentId, classId, date)
✓ bulkMarkPresent(students, classId, className, verifiedBy, verifiedByName, date)
✓ checkAttendanceMilestone(studentId, studentName, createdBy)
✓ checkAnniversaryMilestone(studentId, studentName, createdBy)
✓ getStudentAttendanceCount(studentId)
✓ getTotalStudentAttendanceCount(studentId, initialCount)
✓ getMonthlyStats(month)
✓ getTodayTotal()
✓ getStudentAttendanceRate(studentId, startDate, totalPossibleClasses)
✓ delete(id)
✓ recalculateAchievementsForStudent(studentId, studentName, createdBy)
✓ recalculateAllAchievements(createdBy)
```

### Flutter (Muito Incompleto)
```
✓ getByStudent(studentId, limit)
✓ getStudentAttendanceCount(studentId)
✓ getByDateRange(startDate, endDate, filters)
✓ getByDateAndClass(date, classId)
✓ getTodayByClass(classId)
✓ isStudentPresent(studentId, classId, date)
✓ getPresentStudentIds(classId, date)
✓ getMonthlyStats(year, month)
✓ getTodayTotal()
✓ getCalendarData(studentId, year, month)
✓ getStudentStreak(studentId)

✗ markPresent() - CRÍTICO FALTANDO
✗ unmarkPresent() - CRÍTICO FALTANDO
✗ bulkMarkPresent() - CRÍTICO FALTANDO
✗ checkAttendanceMilestone() - FALTANDO
✗ checkAnniversaryMilestone() - FALTANDO
✗ delete() - FALTANDO
✗ recalculateAchievementsForStudent() - FALTANDO
✗ getStudentAttendanceRate() - FALTANDO
```

**Gap: 45% funcionalidade faltando - CRÍTICO para chamada**

---

## 3. PaymentService/FinancialService - Financeiro

### WebApp (Completo)
```
✓ list(filters)
✓ getById(id)
✓ getByStudent(studentId)
✓ getPending()
✓ getOverdue()
✓ getPaidThisMonth()
✓ getMonthlySummary(month)
✓ create(data, createdBy)
✓ generateMonthlyTuitions(students, month, createdBy)
✓ markAsPaid(id, method, paymentDate)
✓ markOverduePayments() - Batch job
✓ cancel(id)
✓ update(id, data)
✓ delete(id)
✓ getRevenueStats(startDate, endDate)
✓ getWhatsAppReminderLink(phone, studentName, amount, dueDate)
```

### Flutter (Incompleto)
```
✓ getByStudent(studentId, limit)
✓ getPendingByStudent(studentId)
✓ getOverdueByStudent(studentId)
✓ getStatsByStudent(studentId)
✓ getNextDue(studentId)
✓ getById(id)
✓ getByMonth(referenceMonth, studentId)
✓ getSummary()

✗ create() - FALTANDO
✗ update() - FALTANDO
✗ delete() - FALTANDO
✗ markAsPaid() - FALTANDO
✗ cancel() - FALTANDO
✗ generateMonthlyTuitions() - FALTANDO
✗ markOverduePayments() - FALTANDO
✗ getRevenueStats() - FALTANDO
✗ getWhatsAppReminderLink() - FALTANDO
✗ list() com filtros globais - FALTANDO
✗ getPending() global - FALTANDO
✗ getOverdue() global - FALTANDO
```

**Gap: 55% funcionalidade faltando**

---

## 4. ClassService - Aulas

### WebApp (Completo)
```
✓ list()
✓ getById(id)
✓ getByDayOfWeek(dayOfWeek)
✓ getCurrentClass()
✓ getTodayClasses()
✓ getClassesForDate(date)
✓ getByCategory(category)
✓ create(classData)
✓ update(id, data)
✓ delete(id) - Soft delete
✓ hardDelete(id)
✓ getWeeklySchedule()
✓ addStudent(classId, studentId)
✓ removeStudent(classId, studentId)
✓ toggleStudent(classId, studentId)
```

### Flutter (Incompleto)
```
✓ list()
✓ getById(id)
✓ getByDayOfWeek(dayOfWeek)
✓ getTodayClasses()
✓ getCurrentClass()
✓ getByCategory(category)
✓ getWeeklySchedule()

✗ create() - FALTANDO
✗ update() - FALTANDO
✗ delete() - FALTANDO
✗ hardDelete() - FALTANDO
✗ addStudent() - FALTANDO
✗ removeStudent() - FALTANDO
✗ toggleStudent() - FALTANDO
✗ getClassesForDate() - FALTANDO
```

**Gap: 50% funcionalidade faltando**

---

## 5. BeltProgressionService - Graduação

### WebApp (Completo)
```
✓ getByStudent(studentId)
✓ getById(id)
✓ checkEligibility(studentId)
✓ getEligibleStudents()
✓ promote(studentId, newBelt, newStripes, promotedBy, promotedByName, notes)
✓ addStripe(studentId, promotedBy, promotedByName, notes)
✓ changeBelt(studentId, newBelt, promotedBy, promotedByName, notes)
✓ getBeltDistribution()
✓ getRecentPromotions(limit)
✓ getStudentJourney(studentId)
✓ getBeltLabel(belt)
✓ getBeltColorHex(belt)
```

### Flutter (Muito Incompleto)
```
✓ getNextPromotion(currentBelt, currentStripes)
✓ checkEligibility(currentBelt, currentStripes, totalClasses)
✓ calculateProgress(currentBelt, currentStripes, totalClasses)
✓ getClassesToNextStripe(currentBelt, currentStripes, totalClasses)

✗ getByStudent() - FALTANDO
✗ getById() - FALTANDO
✗ promote() - CRÍTICO FALTANDO
✗ addStripe() - CRÍTICO FALTANDO
✗ changeBelt() - CRÍTICO FALTANDO
✗ getEligibleStudents() - FALTANDO
✗ getBeltDistribution() - FALTANDO
✗ getRecentPromotions() - FALTANDO
✗ getStudentJourney() - FALTANDO
```

**Gap: 70% funcionalidade faltando - CRÍTICO para graduação**

---

## 6. SettingsService - Personalização Academia

### WebApp (Completo)
```
✓ getAcademySettings()
✓ saveAcademySettings(settings)
✓ updateLogo(logoUrl)
✓ toggleAbacatePay(enabled, apiKey)
✓ updateAutoGraduation(enabled, attendances)
✓ getAcademy()
```

### Flutter (Incompleto)
```
✓ getAcademySettings()
✓ getAcademyName()
✓ getLogoUrl()
✓ getPixInfo()
✓ isAbacatePayEnabled()
✓ isAutoGraduationEnabled()
✓ getAutoGraduationAttendances()
✓ isStoreEnabled()

✗ saveAcademySettings() - CRÍTICO FALTANDO
✗ updateLogo() - FALTANDO
✗ toggleAbacatePay() - FALTANDO
✗ updateAutoGraduation() - FALTANDO
```

**Gap: 40% funcionalidade faltando**

---

## 7. Serviços Completamente Faltando

### AbacatePayService - PIX/Pagamentos Online
```
✗ isEnabled()
✗ createPixPayment(amount, description, financialId, studentId, studentName)
✗ handleWebhook(payload)
✗ updateWalletBalance(amount, operation)
✗ getWallet()
✗ getTransactions(limit)
✗ requestWithdrawal(amount, pixKey, pixKeyType)
✗ getPaymentStatus(financialId)
```

### StoreService - Loja
```
✗ getProducts()
✗ getActiveProducts()
✗ getProductById(id)
✗ createProduct(data)
✗ updateProduct(id, data)
✗ deleteProduct(id)
✗ updateStock(id, quantity)
✗ decrementStock(id, amount)
✗ createOrder(data)
✗ getOrders()
✗ getOrdersByStatus(status)
✗ getOrdersByStudent(studentId)
✗ getOrderById(id)
✗ updateOrderStatus(id, status)
✗ cancelOrder(id)
✗ generateOrderPayment(orderId)
✗ handlePaymentConfirmation(orderId, transactionId)
```

---

## 8. Hooks/Providers Comparativo

### WebApp Hooks
| Hook | Funcionalidades |
|------|-----------------|
| useStudents | Infinite scroll, filtros, busca, CRUD, stats |
| useAttendance | Chamada completa, bulk ops, otimistic updates |
| useFinancial | CRUD, geração mensal, stats, WhatsApp |
| useBeltProgression | Promoção, elegibilidade, distribuição |
| useAssessment | CRUD, evolução, performance |
| useClasses | CRUD, enrollment |
| usePlans | CRUD, enrollment |
| useAcademySettings | CRUD completo |
| useStore | Produtos, pedidos, carrinho |

### Flutter Providers
| Provider | Funcionalidades |
|----------|-----------------|
| Auth Providers | Login, registro, perfil |
| Student Providers | Read-only queries |
| Portal Providers | Read-only queries |

**Gap: Flutter tem apenas 30% das funcionalidades de hooks**

---

## Prioridades de Implementação

### P0 - CRÍTICO (Necessário para operação)
1. AttendanceService - markPresent, unmarkPresent, bulkMarkPresent
2. BeltProgressionService - promote, addStripe, changeBelt
3. StudentService - create, delete, quickCreate
4. PaymentService - create, markAsPaid, cancel

### P1 - IMPORTANTE (Gestão completa)
1. ClassService - CRUD completo
2. PlanService - CRUD completo
3. SettingsService - saveAcademySettings
4. CompetitionService - CRUD e enrollment

### P2 - DESEJÁVEL (Features extras)
1. AbacatePayService - Pagamentos PIX
2. StoreService - Loja
3. NotificationService - Templates
4. LinkCodeService - Geração

---

## Conclusão

O app Flutter atualmente tem **~40% da funcionalidade** do webapp.

Principais gaps:
- **Operações de escrita quase inexistentes** - A maioria dos serviços só lê dados
- **Chamada de alunos não funcional** - Não pode marcar presença
- **Graduação não funcional** - Não pode promover alunos
- **Financeiro incompleto** - Não pode criar/marcar pagamentos
- **Loja inexistente**
- **Pagamentos PIX inexistentes**
