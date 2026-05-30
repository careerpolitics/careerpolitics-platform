import { h, render } from 'preact';
import { MockExamListing } from '../mockExams/MockExamListing';
import { MockExamDetail } from '../mockExams/MockExamDetail';
import { MockExamInterface } from '../mockExams/MockExamInterface';
import { ExamResults } from '../mockExams/ExamResults';
import { UserMockExamDashboard } from '../mockExams/UserMockExamDashboard';

function mountComponent(id, Component) {
  const root = document.getElementById(id);
  if (!root) return;

  const props = root.dataset.props
    ? JSON.parse(root.dataset.props)
    : {};

  render(<Component {...props} />, root);
}

function init() {
  mountComponent('mock-exam-listing', MockExamListing);
  mountComponent('mock-exam-detail', MockExamDetail);
  mountComponent('mock-exam-interface', MockExamInterface);
  mountComponent('mock-exam-results', ExamResults);
  mountComponent('mock-exam-dashboard', UserMockExamDashboard);
}

if (
  document.readyState === 'interactive' ||
  document.readyState === 'complete'
) {
  init();
} else {
  document.addEventListener('DOMContentLoaded', init);
}

if (window.InstantClick) {
  window.InstantClick.on('change', init);
}
