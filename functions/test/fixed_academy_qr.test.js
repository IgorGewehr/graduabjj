'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  acceptsStudent,
  attendanceDayKey,
  eligibleClass,
  scheduleOccurrenceInWindow,
  studentIdFromMapping,
} = require('../fixed_academy_qr')._internals;

test('legacy class with empty roster accepts any academy student', () => {
  assert.equal(acceptsStudent({studentIds: []}, 'student-a'), true);
});

test('strict class only accepts enrolled students', () => {
  const cls = {isOpenClass: false, studentIds: ['student-a']};
  assert.equal(acceptsStudent(cls, 'student-a'), true);
  assert.equal(acceptsStudent(cls, 'student-b'), false);
});

test('check-in window opens 30 minutes before and closes 60 after', () => {
  const schedule = {dayOfWeek: 1, startTime: '19:00', endTime: '20:00'};
  assert.ok(scheduleOccurrenceInWindow(schedule, new Date(2026, 7, 10, 18, 30)));
  assert.ok(scheduleOccurrenceInWindow(schedule, new Date(2026, 7, 10, 21, 0)));
  assert.equal(
    scheduleOccurrenceInWindow(schedule, new Date(2026, 7, 10, 18, 29)),
    null,
  );
});

test('overnight schedule remains eligible after midnight', () => {
  const schedule = {dayOfWeek: 1, startTime: '23:30', endTime: '00:30'};
  assert.ok(scheduleOccurrenceInWindow(schedule, new Date(2026, 7, 11, 0, 20)));
});

test('eligibleClass combines active, roster and schedule gates', () => {
  const now = new Date(2026, 7, 10, 19, 15);
  const cls = {
    isActive: true,
    isOpenClass: false,
    studentIds: ['student-a'],
    schedule: [{dayOfWeek: 1, startTime: '19:00', endTime: '20:00'}],
  };
  assert.ok(eligibleClass(cls, 'student-a', now));
  assert.equal(eligibleClass(cls, 'student-b', now), null);
  assert.equal(eligibleClass({...cls, isActive: false}, 'student-a', now), null);
});

test('attendance id day key uses local calendar date', () => {
  assert.equal(attendanceDayKey(new Date(2026, 0, 2, 23, 59)), '20260102');
});

test('student id is derived only from academy membership mapping', () => {
  const mapping = {
    academyDetails: {
      academyA: {studentId: 'student-a'},
    },
  };
  assert.equal(studentIdFromMapping(mapping, 'academyA'), 'student-a');
  assert.equal(studentIdFromMapping(mapping, 'academyB'), null);
});
